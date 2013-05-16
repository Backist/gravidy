#include "dynamics_gpu.cuh"

inline __host__ __device__ Forces operator+(Forces &a, Forces &b)
{
    Forces tmp;
    tmp.a[0] = a.a[0] + b.a[0];
    tmp.a[1] = a.a[1] + b.a[1];
    tmp.a[2] = a.a[2] + b.a[2];

    tmp.a1[0] = a.a1[0] + b.a1[0];
    tmp.a1[1] = a.a1[1] + b.a1[1];
    tmp.a1[2] = a.a1[2] + b.a1[2];

    return tmp;
}

inline __host__ __device__ void operator+=(Forces &a, Forces &b)
{
    a.a[0] += b.a[0];
    a.a[1] += b.a[1];
    a.a[2] += b.a[2];

    a.a1[0] += b.a1[0];
    a.a1[1] += b.a1[1];
    a.a1[2] += b.a1[2];
}


__host__ void gpu_init_acc_jrk()
{
    int smem = BSIZE * 2* sizeof(double4);
    k_init_acc_jrk <<< nblocks, nthreads, smem >>> (d_r, d_v, d_f, d_m, n);
    #ifdef KERNEL_ERROR_DEBUG
        std::cerr << "k_init_acc_jrk: " << std::endl;
        std::cerr << cudaGetErrorString(cudaGetLastError()) << std::endl;
    #endif
}

__host__ double gpu_energy()
{

    CUDA_SAFE_CALL(cudaMemcpy(d_r,  h_r,  d4_size,cudaMemcpyHostToDevice));
    CUDA_SAFE_CALL(cudaMemcpy(d_v,  h_v,  d4_size,cudaMemcpyHostToDevice));
    k_energy <<< nblocks, nthreads >>> (d_r, d_v, d_ekin, d_epot, d_m, n);
    #ifdef KERNEL_ERROR_DEBUG
        std::cerr << "k_energy: " << std::endl;
        std::cerr << cudaGetErrorString(cudaGetLastError()) << std::endl;
    #endif

    CUDA_SAFE_CALL(cudaMemcpy(h_ekin, d_ekin, d1_size,cudaMemcpyDeviceToHost));
    CUDA_SAFE_CALL(cudaMemcpy(h_epot, d_epot, d1_size,cudaMemcpyDeviceToHost));

    // Reduction on CPU
    ekin = 0.0;
    epot = 0.0;

    for (int i = 0; i < n; i++) {
        ekin += h_ekin[i];
        epot += h_epot[i];
    }
    return ekin + epot;
}

__host__ void gpu_update_acc_jrk_simple(int total) {

    int smem = BSIZE * sizeof(Predictor);
    //Predictor tmp[total];

    //dim3 nthreads(BSIZE, 1, 1);
    //dim3 nblocks(1 + (total-1)/BSIZE,NJBLOCK, 1);
    k_update_acc_jrk_simple <<< nblocks, nthreads, smem >>> (d_p, d_f,
                                                             d_m, d_move, n, total);
    //cudaThreadSynchronize();
    #ifdef KERNEL_ERROR_DEBUG
        std::cerr << "k_update_acc_jrk_simple: " << std::endl;
        std::cerr << cudaGetErrorString(cudaGetLastError()) << std::endl;
    #endif
}

__global__ void reduce(Forces *d_in,
                       Forces *d_out,
                       unsigned int total)
{
    extern __shared__ Forces sdata[];

    const int xid   = threadIdx.x;
    const int bid   = blockIdx.x;
    const int iaddr = xid + blockDim.x * bid;

    sdata[xid] = d_in[iaddr];
    __syncthreads();

    if(xid < 8) sdata[xid] += sdata[xid + 8];
    if(xid < 4) sdata[xid] += sdata[xid + 4];
    if(xid < 2) sdata[xid] += sdata[xid + 2];
    if(xid < 1) sdata[xid] += sdata[xid + 1];

    if(xid == 0){
        d_out[bid] = sdata[0];
    }
}

__host__ void gpu_update(int total) {

    // Fill the h_i Predictor array with the particles that we need
    // to move in this iteration
    for (int i = 0; i < total; i++) {
        int id = h_move[i];
        h_i[i] = h_p[id];
    }

    // Copy to the GPU (d_i) the preddictor host array (h_i)
    CUDA_SAFE_CALL(cudaMemcpy(d_i, h_i, sizeof(Predictor) * total, cudaMemcpyHostToDevice));


    // Blocks and Threads configuration
    dim3 nblocks(1 + (total-1)/BSIZE,NJBLOCK, 1);
    dim3 nthreads(BSIZE, 1, 1);
    size_t smem = BSIZE * sizeof(Predictor);

    // Kernel call
    k_update <<< nblocks, nthreads, smem >>> (d_i, d_p, d_fout,d_m, n, total);
    #ifdef KERNEL_ERROR_DEBUG
        td::cerr << "k_update: " << std::endl;
        std::cerr << cudaGetErrorString(cudaGetLastError()) << std::endl;
    #endif

    dim3 rgrid   (total,   1, 1);
    dim3 rthreads(NJBLOCK, 1, 1);
    size_t smem2 = sizeof(Forces) * NJBLOCK + 1;
    reduce <<< rgrid, rthreads, smem2 >>>(d_fout, d_fout_tmp, total);
    #ifdef KERNEL_ERROR_DEBUG
        std::cerr << "k_reduce: " << std::endl;
        std::cerr << cudaGetErrorString(cudaGetLastError()) << std::endl;
    #endif

    CUDA_SAFE_CALL(cudaMemcpy(h_fout_tmp, d_fout_tmp, sizeof(Forces) * total, cudaMemcpyDeviceToHost));

    for (int i = 0; i < total; i++) {
        int id = h_move[i];
        h_f[id] = h_fout_tmp[i];
    }

}
