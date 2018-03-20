#include "demo.h"
#include <demo_util.h>

#include <mpi.h>
#include <math.h>
#include <stdio.h>
#include <stddef.h>

#define PI 3.14159265358979323846264338327

double utrue(double x)
{
    double u;
    double pi2;
    pi2 = 2*PI;
    u = cos(pi2*x);
    return u;
}

typedef struct 
{
    double a;
    double b; 
    int n_global;
} struct_domain_t;

void build_domain_type(MPI_Datatype *domain_t)
{
    int block_lengths[3] = {1,1,1};

    /* Set up types */
    MPI_Datatype typelist[3];
    typelist[0] = MPI_DOUBLE;
    typelist[1] = MPI_DOUBLE;
    typelist[2] = MPI_INT;

    /* Set up displacements */
    MPI_Aint disp[3];
    disp[0] = offsetof(struct_domain_t,a);
    disp[1] = offsetof(struct_domain_t,b);
    disp[2] = offsetof(struct_domain_t,n_global);

    MPI_Type_create_struct(3,block_lengths, disp, typelist, domain_t);
    MPI_Type_commit(domain_t);
}



void main(int argc, char** argv)
{
    /* Data arrays */
    double *x, *u;
    double range[2];
    struct_domain_t domain;


    /* File I/O */
    // MPI_Offset offset;
    MPI_File   file;
    MPI_Status status;
    
    /* Data type */
    MPI_Datatype domain_t;
    MPI_Datatype num_as_string;
    MPI_Datatype localarray;

    int j;

    const int charspernum = 21;

    /* MPI variables */
    int my_rank, nprocs;

    MPI_Init(&argc, &argv);

    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    set_rank(my_rank);  /* Used in printing */
    read_loglevel(argc,argv);

    MPI_Comm_size(MPI_COMM_WORLD, &nprocs);

    if (my_rank == 0)
    {        
        int m,err,loglevel;
        read_int(argc,argv, "-m", &m, &err);
        if (err > 0)
        {
            print_global("Command line argument '-m' not found\n");
            exit(0);
        }        

        domain.n_global = pow2(m);     /* Number of sub-intervals used for integration */

        /* Hardwire values */
        domain.a = 0;
        domain.b = 1;  
    }

    build_domain_type(&domain_t);

    /* Broadcast global information */
    int root = 0;
    MPI_Bcast(&domain.a,1,domain_t,root,MPI_COMM_WORLD);

    double w = (domain.b-domain.a)/nprocs;    
    int m = domain.n_global/nprocs;   /* Number of panels in each section */

    range[0] = domain.a + my_rank*w;
    range[1] = range[0] + w;
    double h = (range[1] - range[0])/m;

    /* ---------------------------------------------------------------
       Set up array to write out
    --------------------------------------------------------------- */
    linspace_array(range[0],range[1],m+1,&x);
    int nsize = my_rank < nprocs-1 ? m : m+1;
    zeros_array(nsize,&u);

    for(j = 0; j < nsize; j++)
    {
        u[j] = utrue(x[j]);
    }

    /* ----------------------------------------------------------------
       Write out file
    ---------------------------------------------------------------- */
    /* each line is represented by charspernum chars */
    MPI_Type_contiguous(charspernum, MPI_CHAR, &num_as_string); 
    MPI_Type_commit(&num_as_string); 

    /* convert our data into txt */
    char *text;
    char_array(nsize*charspernum,&text);
    for (j = 0; j < nsize; j++) 
    {
        sprintf(&text[j*charspernum],"%20.12f\n",u[j]);            
    }

    int globalsize = domain.n_global+1;  /* Leave extra space */
    int localsize = nsize;
    int starts = m*my_rank;
    int order = MPI_ORDER_C;

    MPI_Type_create_subarray(1, &globalsize, &localsize, &starts, order, 
                             num_as_string, &localarray);
    MPI_Type_commit(&localarray);

    /* Open file for real */
    MPI_File_open(MPI_COMM_WORLD, "text.out", 
                  MPI_MODE_CREATE|MPI_MODE_WRONLY,
                  MPI_INFO_NULL, &file);

    /* Print out header */
    int hlen = charspernum;
    int header_size = 3*hlen;  /* Leave room for comments */
    if (my_rank == 0)
    {

        char *header;
        char_array(header_size,&header);
        sprintf(&header[0*hlen],"%20.8f\n", domain.a); /* 15 lines each */
        sprintf(&header[1*hlen],"%20.8f\n", domain.b);
        sprintf(&header[2*hlen],"%20d\n", domain.n_global);
        MPI_File_write(file,header,header_size,MPI_CHAR,MPI_STATUS_IGNORE);
        delete_array((void*) &header);
    }


    MPI_Offset offset = header_size;
    MPI_File_set_view(file, offset,  MPI_CHAR, localarray, 
                           "native", MPI_INFO_NULL);

    MPI_File_write_all(file, text, localsize, num_as_string,MPI_STATUS_IGNORE);
    MPI_File_close(&file);

    MPI_Type_free(&localarray);
    MPI_Type_free(&num_as_string);    


    delete_array((void*) &x);
    delete_array((void*) &u);

    MPI_Finalize();

}