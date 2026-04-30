#include <algorithm>

#include "mu/mu.hpp"

void sort_with_ndarray_data(int* arr, int size)
{
    std::sort(arr, arr + size);
}

void sort_with_ndarray(mu::NDArray<int> arr)
{
    std::sort(arr.data(), arr.data() + arr.numElements());
}

void sort_with_ptr(int* arr, int size)
{
    auto taskIdx = mu::getTaskIdx();
    auto offset = static_cast<size_t>(taskIdx) * static_cast<size_t>(size);
    auto curArray = &arr[offset];
    std::sort(curArray, curArray + size);
}
MU_KERNEL_ADD(sort_with_ndarray_data);
MU_KERNEL_ADD(sort_with_ndarray);
MU_KERNEL_ADD(sort_with_ptr);
