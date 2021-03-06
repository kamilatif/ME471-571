#include <stdio.h>
#include <sys/time.h>
#include <demo_util.h>
#include <cuda_util.h>

__global__ void addmat(int m, int n, int* A, int *B, int *C) 
{
    /* Each thread processes one element */
    unsigned int ix = threadIdx.x + blockIdx.x*blockDim.x;
    unsigned int iy = threadIdx.y + blockIdx.y*blockDim.y;
    int idx = iy*m + ix; 
    if (ix < m && iy < n)   
        C[idx] = A[idx] + B[idx];
}

__global__ void addmat2(int m, int n, int* A, int *B, int *C) 
{    
    /* blockDim.x = 1; blockDim.y = n/gridDim.y */
    unsigned int ix;
    unsigned int iy = threadIdx.y + blockIdx.y*blockDim.y;
    if (iy < n)
    {
        for(ix = 0; ix < m; ix++)
        {
            int idx  = iy*m + ix; 
            C[idx]   = A[idx]   + B[idx];            
        }
    }
}

__global__ void addmat3(int m, int n, int* A, int *B, int *C) 
{    
    /* blockDim.x = m/gridDim.x; blockDim.y = 1 */
    unsigned int ix = threadIdx.x + blockIdx.x*blockDim.x;
    unsigned int iy;
    if (ix < m)
    {
        for(iy = 0; iy < n; iy++)
        {
            int idx  = iy*m + ix; 
            C[idx]   = A[idx]   + B[idx];            
        }
    }
}


double cpuSecond()
{
    struct timeval tp;
    gettimeofday(&tp,NULL);
    return (double) tp.tv_sec + (double)tp.tv_usec*1e-6;
}


int main(int argc, char** argv) 
{
    /* Host */
    int *A, *B, *C;

    /* Device */
    int *dev_A, *dev_B, *dev_C;

    /* scalars */
    size_t m, n, nbytes;
    double etime, start;

    int dimx, dimy;

    int err1, err2; 
    read_int(argc, argv, "--dimx", &dimx, &err1);
    read_int(argc, argv, "--dimy", &dimy, &err2);

    if (err1 > 0 || err2 > 0)
    {
        printf("Problem reading dimx or dimy\n");
        exit(0);
    }

    /* Matrix is m x n */
    m = 1 << 14;  
    n = 1 << 14;  

    nbytes = m*n*sizeof(int);

    printf("--------------- Memory -------------\n");
    printf("%20s %10d\n","m",m);
    printf("%20s %10d\n","n",n);
    printf("%20s %10.1f (mb)\n","Memory",3*nbytes/(1024.0*1024.0));
    printf("%20s %10.1f (gb)\n","Memory",3*nbytes/(1024.0*1024.0*1024.0));
    printf("\n");

    A = (int*) malloc(nbytes);
    B = (int*) malloc(nbytes);
    C = (int*) malloc(nbytes);

    int k;
    for(k = 0; k < m*n; k++)
    {
        A[k] = 1;
        B[k] = 2;
    }

    /* Allocate memory on the device */
    printf("----------- Initialization ---------\n");
    start = cpuSecond();
    cudaMalloc((void**) &dev_A, nbytes);
    cudaMalloc((void**) &dev_B, nbytes);
    cudaMalloc((void**) &dev_C, nbytes);
    etime = cpuSecond() - start;
    printf("%20s %10.3g (s)\n","cudaMalloc",etime);

    start = cpuSecond();
    cudaMemcpy(dev_A, A, nbytes, cudaMemcpyHostToDevice);
    cudaMemcpy(dev_B, B, nbytes, cudaMemcpyHostToDevice);
    etime = cpuSecond() - start;
    printf("%20s %10.3g (s)\n","Copy (HtoD)",etime);


    /* Launch nx blocks, each with ny threads */

    dim3 block(dimx, dimy);  /* Distribute each row to blocks */
    dim3 grid;

    start = cpuSecond();
    if (dimx == 1 && dimy > 1)
    {   
        /* Thread runs over ix */
        grid.x = 1;
        grid.y = (n+block.y-1)/block.y;
        addmat2<<<grid,block>>>(m,n,dev_A, dev_B, dev_C);
    }
    else if (dimx > 1 && dimy == 1) 
    {
        /* Thread runs over iy */
        grid.x = (m + block.x - 1)/block.x;
        grid.y = 1;
        // start = cpuSecond();
        addmat3<<<grid,block>>>(m,n,dev_A, dev_B, dev_C);
    }
    else
    {
        grid.x = (m + block.x - 1)/block.x; 
        grid.y = (n + block.y - 1)/block.y;
        //start = cpuSecond();
        addmat<<<grid,block>>>(m,n,dev_A, dev_B, dev_C);
    }
    CHECK(cudaDeviceSynchronize());
    etime = cpuSecond() - start;
    CHECK(cudaPeekAtLastError());
    printf("%20s %10.3g (s)\n","GPU Kernel", etime);

    /* Copy contents from device back to host */
    start = cpuSecond();
    cudaMemcpy(C, dev_C, nbytes, cudaMemcpyDeviceToHost);
    etime = cpuSecond() - start;
    printf("%20s %10.3g (s)\n","Copy (DtoH)", etime);
    printf("\n");

#if 1
    printf("\n");
    printf("----------- Grid/Block Info ---------\n");
    printf("%20s %6d %6d","grid.x, block.x",grid.x, block.x);
    if (m <= block.x*grid.x)
    {
        printf("        m <= block.x*grid.x = %d\n",block.x*grid.x);
    }
    else
    {
        printf("        m > block.x*grid.x = %d\n",block.x*grid.x); 
    }
    printf("%20s %6d %6d","grid.y, block.y",grid.y, block.y);
    if (n <= block.y*grid.y)
    {
        printf("        m <= block.y*grid.y = %d\n",block.y*grid.y);
    }
    else
    {
        printf("        m > block.y*grid.y = %d\n",block.y*grid.y); 
    }
    if (dimx*dimy > 1024)
    {
        printf("\n");
        printf("-----> WARNING : Threads per block exceed 1024.\n");
        printf("\n");
    }
#endif


    printf("\n");

#if 0
    printf("\n");


    printf("\n");
    int i,j;
    k = 0;
    for(j = 0; j < n; j++)
    {
        for(i = 0; i < m; i++)
        {
            printf("C[%2d,%2d] = %d\n",i,j,C[k]);
            k++;
        }
        printf("\n");
    }
#endif    

    cudaFree(dev_A);
    cudaFree(dev_B);
    cudaFree(dev_C);
    free(A);
    free(B);
    free(C);

    cudaDeviceSynchronize();
    cudaDeviceReset();
}


