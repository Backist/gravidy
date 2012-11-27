#include "include/options_parser.hpp"
#include "include/file_utils.hpp"
#include "include/memory.hpp"
#include "include/hermite.hpp"

#include <iostream>
#include <iomanip>
#include <limits>
#include <omp.h>

// General variables of the program
int n;
int iterations;
float total_mass;
double int_time;
double ini_time, end_time;
double init_time;
double energy_ini, energy_end, energy_tmp;
double ekin, epot;
float softening, eta;

// Struct vector to read the input file
std::vector<particle> part;
double4  *h_old_a, *h_old_a1;
double4 *h_p_r, *h_p_v;
double4 *d_old_a, *d_old_a1;
double4 *d_p_r, *d_p_v;


// Host pointers
double *h_ekin, *h_epot;
double *h_t, *h_dt;
float   *h_m;
int *h_move;
double4 *h_r, *h_v, *h_a, *h_a1;
//double4 *h_new_a, *h_new_j;
double4 *h_a2, *h_a3;

// Device pointers
double *d_ekin, *d_epot;
double *d_t, *d_dt;
float   *d_m;
int *d_move;
double4 *d_r, *d_v, *d_a, *d_j;
//double4 *d_new_a, *d_new_j;

// System times
float t_rh, t_cr;

// Options strings
std::string input_file, output_file;

size_t nthreads, nblocks;
size_t d1_size, d4_size;
size_t f1_size, i1_size;
double4 *tmp_red;
float *ftmp_red;
/*
 * Main
 */
int
main(int argc, char *argv[])
{
    // Read parameters
    if(!check_options(argc,argv)) return 1;

    read_input_file(input_file);
    init_vectors();
    // TMP
    ini_time = (float)clock()/CLOCKS_PER_SEC;

    // Opening output file for debugging
    out = fopen(output_file.c_str(), "w");

    integrate_gpu();

    end_time = (ini_time - (float)clock()/CLOCKS_PER_SEC);

    fclose(out);
    //write_output_file(output_file);
    clean_vectors();

    return 0;
}