#include <chrono>
#include <cstdio>
#include <cstring>

#include "pxl/pxl.hpp"

// Kernels are defined in mu_kernel/mu_sort.cpp (compiled separately)

int main(int argc, char* argv[])
{
    size_t testCount = 2048;
    size_t sortSize = 64;
    const char* type = "ndarray";
    int deviceId = 0;

    for (int i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "-n") && i + 1 < argc)
            testCount = std::stoull(argv[++i]);
        else if (!strcmp(argv[i], "-s") && i + 1 < argc)
            sortSize = std::stoull(argv[++i]);
        else if (!strcmp(argv[i], "-t") && i + 1 < argc)
            type = argv[++i];
        else if ((!strcmp(argv[i], "-d") || !strcmp(argv[i], "--device")) && i + 1 < argc)
            deviceId = atoi(argv[++i]);
    }

    printf("Device ID = %d\n", deviceId);
    printf("Test configuration: %zu arrays, %zu elements each, with %s\n", testCount, sortSize, type);

    // ── Input data setup ──
    auto context = pxl::createContext(deviceId);
    if (!context)
    {
        printf("Failed to create context\n");
        return 1;
    }
    size_t totalBytes = testCount * sortSize * sizeof(int);
    auto data = reinterpret_cast<int*>(context->memAlloc(totalBytes));
    auto ndarray = pxl::NDArray<int>(data, {testCount, sortSize});

    for (size_t i = 0; i < testCount; i++)
        for (size_t j = 0; j < sortSize; j++)
            data[i * sortSize + j] = sortSize - j;

    // ── Launch setup ──
    auto module = pxl::createModule("mu_kernel/mu_kernel.mubin");
    auto job = context->createJob();
    if (job->load(module) != pxl::Result::Success)
    {
        printf("Job load failed\n");
        return 1;
    }

    const char* kernelName = !strcmp(type, "ndarraydata") ? "sort_with_ndarray_data" : "sort_with_ndarray";
    auto* func = module->createFunction(kernelName);
    auto executor = job->buildMap(func, testCount);
    executor->setInput(data);
    executor->setOutput(data);

    // ── Launch kernel ──
    auto start = std::chrono::steady_clock::now();

    if (executor->execute(ndarray, sortSize) != pxl::Result::Success)
    {
        printf("Map execution failed\n");
        return 1;
    }
    if (executor->synchronize() != pxl::Result::Success)
    {
        printf("Map synchronization failed\n");
        return 1;
    }

    auto elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start);
    printf("test done : %.2f ms\n", elapsed.count());

    // ── Verify ──
    for (size_t i = 0; i < testCount; i++)
        for (size_t j = 0; j < sortSize; j++)
            if (data[i * sortSize + j] != (int)(j + 1))
            {
                printf("Verification failed at [%zu][%zu]\n", i, j);
                return 1;
            }

    context->memFree(data);
    context->destroyJob(job);
    pxl::destroyContext(context);
    return 0;
}
