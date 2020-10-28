#include "drake/multibody/fem/dev/linear_elasticity_model_cache.h"

#include <vector>

namespace drake {
namespace multibody {
namespace fem {
template <typename T>
void LinearElasticityModelCache<T>::DoUpdateCache(
    const std::vector<Matrix3<T>>& F) {
  for (int i = 0; i < this->num_quads(); ++i) {
    strain_[i] = 0.5 * (F[i] + F[i].transpose()) - Matrix3<T>::Identity();
    trace_strain_[i] = strain_[i].trace();
  }
}
}  // namespace fem
}  // namespace multibody
}  // namespace drake
DRAKE_DEFINE_CLASS_TEMPLATE_INSTANTIATIONS_ON_DEFAULT_NONSYMBOLIC_SCALARS(
    class ::drake::multibody::fem::LinearElasticityModelCache);
