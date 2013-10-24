classdef PlanarRigidBodyManipulator < RigidBodyManipulator
  % This class wraps the planar pieces of the spatial vector library (v1)
  % provided by Roy Featherstone on his website:
  %   http://users.cecs.anu.edu.au/~roy/spatial/documentation.html
  
  properties (SetAccess=protected)
    x_axis_label;
    y_axis_label;
    x_axis;
    y_axis;
    view_axis;
    
    T_2D_to_3D;
  end
  
  methods
    function obj = PlanarRigidBodyManipulator(urdf_filename,options)
      % Constructs a PlanarRigidBodyManipulator
      % 
      % @param urdf_filename string path+filename for a .urdf file to parse
      % @option view is a string which must be one of 'right','front', or
      % 'top'.  
      %
      % see also the options described in RigidBodyManipulator/parseURDF 
      %  (the options for this function call are passed through to
      %  parseURDF)
      
      
      obj = obj@RigidBodyManipulator();
      obj.dim = 2;
      
      if (nargin<1) urdf_filename=''; end
      if (nargin<2) options = struct(); end
      if (~isfield(options,'view')) 
        options.view = 'right';
      else
        options.view = lower(options.view);
        if ~any(strcmp(options.view,{'front','right','top'}))
          error('supported view options are front,back,top,bottom,right,or left');
        end
      end
            
      switch options.view % joint_axis = view_axis => counter-clockwise
        case 'front'
          obj.x_axis = [0;1;0];
          obj.y_axis = [0;0;1];
          obj.view_axis = [1;0;0];
          obj.x_axis_label='y';
          obj.y_axis_label='z';
          %          obj.name = [obj.name,'Front'];
        case 'right'
          obj.x_axis = [1;0;0];
          obj.y_axis = [0;0;1];
          obj.view_axis = [0;1;0];
          obj.x_axis_label='x';
          obj.y_axis_label='z';
          %          obj.name = [obj.name,'Right'];
        case 'top'
          obj.x_axis = [1;0;0];
          obj.y_axis = [0;1;0];
          obj.view_axis = [0;0;1];
          obj.x_axis_label='x';
          obj.y_axis_label='y';
          %          obj.name = [obj.name,'Top'];
      end
      obj.T_2D_to_3D = [obj.x_axis, obj.y_axis];
      valuecheck(svd(obj.T_2D_to_3D),[1;1]);  % assert that it's orthonormal
      
      if ~isempty(urdf_filename)
        if ~isfield(options,'namesuffix') options.namesuffix=''; end
        options.namesuffix = [upper([obj.x_axis_label,obj.y_axis_label]),options.namesuffix];
        obj = addRobotFromURDF(obj,urdf_filename,zeros(3,1),zeros(3,1),options);
      end
      
    end
        
    function model = addRobotFromURDF(model,urdf_filename,xyz,rpy,options)
      if nargin<3, xyz = zeros(3,1); end
      if nargin<4, rpy = zeros(3,1); end
      if nargin<5, options=struct(); end
      
      if ~isfield(options,'visual_geometry') options.visual_geometry = true; end
      model = addRobotFromURDF@RigidBodyManipulator(model,urdf_filename,xyz,rpy,options);
      
      if ~isfield(options,'q_nominal') options.q_nominal = zeros(getNumDOF(model),1); end
      kinsol = doKinematics(model,options.q_nominal);

      for i=1:length(model.body)
        body = model.body(i);
        
        %% cleanup 3D geometry for 2D
        for j=1:length(body.geometry)
          pts = model.T_2D_to_3D'*forwardKin(model,kinsol,i,body.geometry{j}.xyz);
          ind = convhull(pts(1,:),pts(2,:));
          model.body(i).geometry{j}.xyz = model.body(i).geometry{j}.xyz(:,ind);
        end
        
        %% weld all joints that are not aligned with the view axis
        if ~body.parent, continue; end
        assert(body.floating == 0,'Drake:PlanarRigidBodyManipulator','Shouldn''t get here.  Planar models should only have RPY floating bases, which are added as individual joints');
        
        view_axis_in_joint_frame = body.T_body_to_joint * [bodyKin(model,kinsol,i,[model.view_axis,zeros(3,1)]); 1,1];
        view_axis_in_joint_frame = view_axis_in_joint_frame(1:3,1)-view_axis_in_joint_frame(1:3,2);

        if isinf(body.pitch) % then it's a prismatic joint
          if abs(dot(view_axis_in_joint_frame,[0;0;1]))>1e-6
            model.body(i).pitch = nan;  % weld joint
          end
        else % then it's a revolute joint
          % todo: handle joint sign logic here
          if abs(dot(view_axis_in_joint_frame,[0;0;1]))<1-1e-6
            model.body(i).pitch = nan;  % weld joint
          end
        end          
      end
      
      model = compile(model);
    end
    
    function model = addFloatingBase(model,parent,rootlink,xyz,rpy,type)
      % just add RPY (intrisic), because the out-of-plane joints will be welded 
      model = addFloatingBase@RigidBodyManipulator(model,parent,rootlink,xyz,rpy,'RPY');
    end
    
    function model = compile(model)
      model = compile@RigidBodyManipulator(model);
      model = model.setNumPositionConstraints(2*length(model.loop));
    end
    
    function v=constructVisualizer(obj,options)
      checkDirty(obj);
      if nargin<2, options=struct(); end
      if ~isfield(options,'viewer') || strcmp(options.viewer('PlanarRigidBodyVisualizer')) 
        v = PlanarRigidBodyVisualizer(obj);
      else
        v = constructVisualizer@RigidBodyManipulator(obj,options);
      end
    end
    
    function t=surfaceTangents(obj,normal)
      % Follows surfaceTangents in RigidBodyManipulator, but produces only
      % a single tangent for each normal (instead of m), and restricts this
      % to the x-y plane.
      
      normal = obj.T_2D_to_3D'*normal;

      % if the normal is [0;0] (because it was aligned with the viewing
      % access), then just set it arbitrarily to [0;1] because I want to
      % treat it as contact, but still avoid the singularity.
      zeroind = sum(normal.^2,1)<1e-6;
      normal(1,zeroind)=0; normal(2,zeroind)=1;
      
      % for each n, it looks like:
      % if (abs(normal(2))>abs(normal(1))) t = [1,-n(1)/n(2)];
      % else t = [-n(2)/n(1),1]; end
      % and the vectorized form is:
      t=normal; % initialize size
      ind=abs(normal(2,:))>abs(normal(1,:));
      t(:,ind) = [ones(1,sum(ind));-normal(1,ind)./normal(2,ind)];
      ind=~ind;
      t(:,ind) = [-normal(2,ind)./normal(1,ind); ones(1,sum(ind))];
      t = t./repmat(sqrt(sum(t.^2,1)),2,1); % normalize
      t = {obj.T_2D_to_3D*t};
      
      % NOTEST
    end
    
  end
  
end

