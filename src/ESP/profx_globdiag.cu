// ==============================================================================
// This file is part of THOR.
//
//     THOR is free software : you can redistribute it and / or modify
//     it under the terms of the GNU General Public License as published by
//     the Free Software Foundation, either version 3 of the License, or
//     (at your option) any later version.
//
//     THOR is distributed in the hope that it will be useful,
//     but WITHOUT ANY WARRANTY; without even the implied warranty of
//     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
//     GNU General Public License for more details.
//
//     You find a copy of the GNU General Public License in the main
//     THOR directory under <license.txt>.If not, see
//     <http://www.gnu.org/licenses/>.
// ==============================================================================
//
// Calculates energy, angular momentum, and mass of atmosphere
//
//
// Known limitations: - Runs in a single GPU.
//
// Known issues: None
//
//
// If you use this code please cite the following reference:
//
//       [1] Mendonca, J.M., Grimm, S.L., Grosheintz, L., & Heng, K., ApJ, 829, 115, 2016
//
// Current Code Owners: Joao Mendonca (joao.mendonca@space.dtu.dk)
//                      Russell Deitrick (russell.deitrick@csh.unibe.ch)
//                      Urs Schroffenegger (urs.schroffenegger@csh.unibe.ch)
//
// History:
// Version Date       Comment
// ======= ====       =======
// 2.0     30/11/2018 Released version (RD & US)
// 1.0     16/08/2017 Released version  (JM)
//
////////////////////////////////////////////////////////////////////////

#include "phy/profx_globdiag.h"

__global__ void CalcTotEnergy(double *Etotal_d,
                              double *GlobalE_d,
                              double *Mh_d,
                              double *W_d,
                              double *Rho_d,
                              double *temperature_d,
                              double  Gravit,
                              double *Cp_d,
                              double *Rd_d,
                              double  A,
                              double *Altitude_d,
                              double *Altitudeh_d,
                              double *lonlat_d,
                              double *areasT,
                              double *func_r_d,
                              int     num,
                              bool    DeepModel) {

    int id  = blockIdx.x * blockDim.x + threadIdx.x;
    int nv  = gridDim.y;
    int lev = blockIdx.y;

    if (id < num) {
        double Ek, Eint, Eg;
        double wx, wy, wz;
        double Cv = Cp_d[id * nv + lev] - Rd_d[id * nv + lev];

        //calculate control volume
        double zup, zlow, Vol;
        zup  = Altitudeh_d[lev + 1] + A;
        zlow = Altitudeh_d[lev] + A;
        if (DeepModel) {
            Vol = areasT[id] / pow(A, 2) * (pow(zup, 3) - pow(zlow, 3)) / 3;
        }
        else {
            Vol = areasT[id] * (zup - zlow);
        }

        //calc cartesian values of vertical wind
        wx = W_d[id * nv + lev] * cos(lonlat_d[id * 2 + 1]) * cos(lonlat_d[id * 2]);
        wy = W_d[id * nv + lev] * cos(lonlat_d[id * 2 + 1]) * sin(lonlat_d[id * 2]);
        wz = W_d[id * nv + lev] * sin(lonlat_d[id * 2 + 1]);

        //kinetic energy density 0.5*rho*v^2
        Ek = 0.5
             * ((Mh_d[id * 3 * nv + lev * 3 + 0] + wx) * (Mh_d[id * 3 * nv + lev * 3 + 0] + wx)
                + (Mh_d[id * 3 * nv + lev * 3 + 1] + wy) * (Mh_d[id * 3 * nv + lev * 3 + 1] + wy)
                + (Mh_d[id * 3 * nv + lev * 3 + 2] + wz) * (Mh_d[id * 3 * nv + lev * 3 + 2] + wz))
             / Rho_d[id * nv + lev];

        //internal energy rho*Cv*T
        Eint = Cv * temperature_d[id * nv + lev] * Rho_d[id * nv + lev];

        //gravitation potential energy rho*g*altitude (assuming g = constant)
        Eg = Rho_d[id * nv + lev] * Gravit * Altitude_d[lev];

        //total energy in the control volume
        Etotal_d[id * nv + lev] = (Ek + Eint + Eg) * Vol;

        // printfn("E = %e\n",Etotal_d[id*nv+lev]);
    }
}

__global__ void
EnergySurface(double *Esurf_d, double *Tsurface_d, double *areasT, double Csurf, int num) {

    // calculate thermal energy held by surface
    int id = blockIdx.x * blockDim.x + threadIdx.x;

    if (id < num) {
        Esurf_d[id] = Csurf * Tsurface_d[id] * areasT[id];
    }
}

__global__ void CalcAngMom(double *AngMomx_d,
                           double *AngMomy_d,
                           double *AngMomz_d,
                           double *GlobalAMx_d,
                           double *GlobalAMy_d,
                           double *GlobalAMz_d,
                           double *Mh_d,
                           double *Rho_d,
                           double  A,
                           double  Omega,
                           double *Altitude_d,
                           double *Altitudeh_d,
                           double *lonlat_d,
                           double *areasT,
                           double *func_r_d,
                           int     num,
                           bool    DeepModel) {

    int id  = blockIdx.x * blockDim.x + threadIdx.x;
    int nv  = gridDim.y;
    int lev = blockIdx.y;

    if (id < num) {
        double AMx, AMy, AMz;
        double rx, ry, rz, r;

        //calculate control volume
        double zup, zlow, Vol;
        zup  = Altitudeh_d[lev + 1] + A;
        zlow = Altitudeh_d[lev] + A;
        if (DeepModel) {
            Vol = areasT[id] / pow(A, 2) * (pow(zup, 3) - pow(zlow, 3)) / 3;
        }
        else {
            Vol = areasT[id] * (zup - zlow);
        }

        //radius vector
        r  = (A + Altitude_d[lev]);
        rx = r * func_r_d[id * 3 + 0];
        ry = r * func_r_d[id * 3 + 1];
        rz = r * func_r_d[id * 3 + 2];

        //angular momentum r x p (total x and y over globe should ~ 0, z ~ const)
        AMx = ry * Mh_d[id * 3 * nv + lev * 3 + 2] - rz * Mh_d[id * 3 * nv + lev * 3 + 1]
              - Rho_d[id * nv + lev] * Omega * r * rz * cos(lonlat_d[id * 2 + 1])
                    * cos(lonlat_d[id * 2]);
        AMy = -rx * Mh_d[id * 3 * nv + lev * 3 + 2] + rz * Mh_d[id * 3 * nv + lev * 3 + 0]
              - Rho_d[id * nv + lev] * Omega * r * rz * cos(lonlat_d[id * 2 + 1])
                    * sin(lonlat_d[id * 2]);
        AMz = rx * Mh_d[id * 3 * nv + lev * 3 + 1] - ry * Mh_d[id * 3 * nv + lev * 3 + 0]
              + Rho_d[id * nv + lev] * Omega * r * r * cos(lonlat_d[id * 2 + 1])
                    * cos(lonlat_d[id * 2 + 1]);
        //AMx, AMy should go to zero when integrated over globe
        // (but in practice, are just much smaller than AMz)

        //total in control volume
        AngMomx_d[id * nv + lev] = AMx * Vol;
        AngMomy_d[id * nv + lev] = AMy * Vol;
        AngMomz_d[id * nv + lev] = AMz * Vol;
    }
}

__global__ void CalcMass(double *Mass_d,
                         double *GlobalMass_d,
                         double *Rho_d,
                         double  A,
                         double *Altitudeh_d,
                         double *lonlat_d,
                         double *areasT,
                         int     num,
                         bool    DeepModel) {

    int id  = blockIdx.x * blockDim.x + threadIdx.x;
    int nv  = gridDim.y;
    int lev = blockIdx.y;

    if (id < num) {
        //calculate control volume
        double zup, zlow, Vol;
        zup  = Altitudeh_d[lev + 1] + A;
        zlow = Altitudeh_d[lev] + A;
        if (DeepModel) {
            Vol = areasT[id] / pow(A, 2) * (pow(zup, 3) - pow(zlow, 3)) / 3;
        }
        else {
            Vol = areasT[id] * (zup - zlow);
        }

        //mass in control volume = density*volume
        Mass_d[id * nv + lev] = Rho_d[id * nv + lev] * Vol;
    }
}


__global__ void CalcEntropy(double *Entropy_d,
                            double *pressure_d,
                            double *temperature_d,
                            double *Cp_d,
                            double *Rd_d,
                            double  A,
                            double  P_Ref,
                            double *Altitude_d,
                            double *Altitudeh_d,
                            double *lonlat_d,
                            double *areasT,
                            double *func_r_d,
                            int     num,
                            bool    DeepModel) {

    int id  = blockIdx.x * blockDim.x + threadIdx.x;
    int nv  = gridDim.y;
    int lev = blockIdx.y;

    if (id < num) {
        double kappa = Rd_d[id * nv + lev] / Cp_d[id * nv + lev];
        double potT  = temperature_d[id * nv + lev] * pow(P_Ref / pressure_d[id * nv + lev], kappa);
        double Sdens = Cp_d[id * nv + lev] * log(potT);

        //calculate control volume
        double zup, zlow, Vol;
        zup  = Altitudeh_d[lev + 1] + A;
        zlow = Altitudeh_d[lev] + A;
        if (DeepModel) {
            Vol = areasT[id] / pow(A, 2) * (pow(zup, 3) - pow(zlow, 3)) / 3;
        }
        else {
            Vol = areasT[id] * (zup - zlow);
        }

        //total energy in the control volume
        Entropy_d[id * nv + lev] = Sdens * Vol;
    }
}
