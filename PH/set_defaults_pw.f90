!
! Copyright (C) 2008 Quantum-Espresso group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
#include "f_defs.h"
!
!----------------------------------------------------------------------------
SUBROUTINE set_defaults_pw
  !-----------------------------------------------------------------------------
  !
  ! ...  this subroutine sets the default values for the variables
  ! ...  read from input by pw which are not saved into the xml file. 
  ! ...  It has to be called by programs that run "electrons" without 
  ! ...  reading the input data. It is possible to change the default
  ! ...  values initialized here. Variables in input_parameters are
  ! ...  initialized by that module  and do not need to be initialized here. 
  ! ...  Actually this routine should not be needed. All the variables
  ! ...  which are read from input should have a default value and should
  ! ...  be in a module that initializes them. The pw code should then
  ! ...  use those variables. Unfortunately the routine input now 
  ! ...  initializes several variables that are in pw modules and
  ! ...  have just a different name from the variable contained in 
  ! ...  input parameters, or are calculated starting from the variable
  ! ...  contained in input_parameters.  
  ! ...  Moreover many variables contained in control_flags are not 
  ! ...  initialized and need to be initialized here ... 
  !
  !
  USE kinds,         ONLY : DP
  USE bp,            ONLY : lberry,   &
                            lelfield
  !
  USE basis,         ONLY : startingwfc, &
                            startingpot
  !
  USE cellmd,        ONLY : calc, lmovecell
  !
  USE force_mod,     ONLY : lforce, lstres
  !
  USE gvect,         ONLY : ecfixed, qcutz, q2sigma
  !
  USE klist,         ONLY : lxkcry, tot_charge, &
                            tot_magnetization, &
                            multiplicity

  USE relax,         ONLY : starting_scf_threshold
  !
  USE control_flags, ONLY : isolve, max_cg_iter, tr2, imix, &
                            nmix, iverbosity, niter, pot_order, wfc_order, &
                            assume_isolated, &
                            diago_full_acc, &
                            mixing_beta, &
                            upscale, &
                            nstep, &
                            iprint, &
                            nosym, &
                            io_level, lscf, lbfgs, lmd, lpath, lneb,   &
                            lsmd, lphonon, ldamped, lbands, lmetadyn, llang, &
                            lconstrain, lcoarsegrained, restart, &
                            use_para_diag

  USE bfgs_module,   ONLY : bfgs_ndim, &
                            trust_radius_max, &
                            trust_radius_min, &
                            trust_radius_ini, &
                            w_1, &
                            w_2
  USE us, ONLY : spline_ps
  USE a2F, ONLY : la2F

  !
  IMPLICIT NONE
  !
  iprint = 100000
  lberry   = .FALSE.
  lelfield = .FALSE.
  lxkcry=.FALSE.
  tot_charge = 0.0_DP
  tot_magnetization = -1
  multiplicity = 0
  nosym = .FALSE.
  ecfixed = 0.0_DP
  qcutz   = 0.0_DP
  q2sigma = 0.01_DP
  !
  !  ... postprocessing of DOS & phonons & el-ph
  la2F = .FALSE.
  !
  ! ... non collinear program variables
  !
  assume_isolated = .FALSE.
  !
  spline_ps = .FALSE.
  !
  diago_full_acc = .FALSE.
  !
  upscale           = 10.0_DP
  mixing_beta       = 0.7
  !
  ! ... BFGS defaults
  !
  bfgs_ndim        = 1
  trust_radius_max = 0.8_DP   ! bohr
  trust_radius_min = 1.E-4_DP ! bohr
  trust_radius_ini = 0.5_DP   ! bohr
  w_1              = 0.01_DP
  w_2              = 0.50_DP
  !
  startingpot = 'file'
  startingwfc = 'atomic'
  !
  restart        = .FALSE.
  !
  io_level = 1
  !
  ! ... various initializations of control variables
  !
  lscf      = .FALSE.
  lmd       = .FALSE.
  lmetadyn  = .FALSE.
  lpath     = .FALSE.
  lneb      = .FALSE.
  lsmd      = .FALSE.
  lmovecell = .FALSE.
  lphonon   = .FALSE.
  lbands    = .FALSE.
  lbfgs     = .FALSE.
  ldamped   = .FALSE.
  lforce    = .FALSE.
  lstres    = .FALSE.
  !
  nstep = 1
  !
  isolve = 1
  max_cg_iter = 100
  use_para_diag = .FALSE.
  !
  niter = 1000
  !
  pot_order = 0
  wfc_order = 0
  !
  tr2=1.D-6
  starting_scf_threshold = tr2
  imix = 0
  nmix = 0
  !
  iverbosity = 0
  !
  calc      = ' '
  !
  RETURN
  !
END SUBROUTINE set_defaults_pw
!
! Copyright (C) 2008 Quantum-ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
#include "f_defs.h"
!
!----------------------------------------------------------------------------
SUBROUTINE setup_nscf()
  !----------------------------------------------------------------------------
  !
  ! ... This routine initializes variables for the non-scf calculations at k 
  ! ... and k+q required by the linear response calculation at finite q.
  ! ... In particular: finds the symmetry group of the crystal that leaves
  ! ... the phonon q-vector (xqq) or the single atomic displacement (modenum)
  ! ... unchanged; determines the k- and k+q points in the irreducible BZ
  ! ... Needed on input (read from data file):
  ! ... "nsym" crystal symmetries s, ftau, t_rev, "nrot" lattice symetries s
  ! ... "nkstot" k-points in the irreducible BZ wrt lattice symmetry
  !
  USE kinds,              ONLY : DP
  USE constants,          ONLY : eps8
  USE parameters,         ONLY : npk
  USE io_global,          ONLY : stdout
  USE constants,          ONLY : pi, degspin
  USE cell_base,          ONLY : at, bg, alat, tpiba, tpiba2, ibrav, &
                                 symm_type, omega
  USE ions_base,          ONLY : nat, tau, ntyp => nsp, ityp, zv
  USE basis,              ONLY : natomwfc
  USE gvect,              ONLY : nr1, nr2, nr3
  USE klist,              ONLY : xk, wk, xqq, nks, nelec, degauss, lgauss, &
                                 nkstot
  USE lsda_mod,           ONLY : lsda, nspin, current_spin, isk, &
                                 starting_magnetization
  USE symme,              ONLY : s, t_rev, irt, ftau, nrot, nsym, invsym, &
                                 time_reversal, sname
  USE wvfct,              ONLY : nbnd, nbndx
  USE control_flags,      ONLY : ethr, isolve, david, &
                                 noinv, nosym, modenum, use_para_diag
  USE mp_global,          ONLY : kunit
  USE spin_orb,           ONLY : domag
  USE noncollin_module,   ONLY : noncolin, m_loc, angle1, angle2
  USE start_k,            ONLY : nks_start, xk_start, wk_start
  USE modes,              ONLY : nsym0 ! TEMP
  !
  IMPLICIT NONE
  !
  REAL (DP), ALLOCATABLE :: rtau (:,:,:)
  INTEGER  :: nsymq
  INTEGER  :: na, nt, irot, isym, is, nb, ierr, ik
  LOGICAL  :: minus_q, magnetic_sym, sym(48)
  !
  INTEGER, EXTERNAL :: n_atom_wfc, copy_sym
  !
  ! ... threshold for diagonalization ethr - should be good for all cases
  !
  ethr= 1.0D-9 / nelec
  !
  ! ... variables for iterative diagonalization (Davidson is assumed)
  !
  isolve = 0
  david = 4
  nbndx = david*nbnd
  natomwfc = n_atom_wfc( nat, ityp )
  !
#ifdef __PARA
  IF ( use_para_diag )  CALL check_para_diag( nelec )
#else
  use_para_diag = .FALSE.
#endif
  !
  ! ... Symmetry and k-point section
  ! ... if nosym is true do not use any point-group symmetry
  !
  IF ( nosym ) nsym = 1
  !
  ! ... time_reversal = use q=>-q symmetry for k-point generation
  !
  magnetic_sym = noncolin .AND. domag 
  time_reversal = .NOT. noinv .AND. .NOT. magnetic_sym
  !
  IF (.not.ALLOCATED(m_loc)) ALLOCATE( m_loc( 3, nat ) )
  IF (noncolin.and.domag) THEN
     DO na = 1, nat
        !
        m_loc(1,na) = starting_magnetization(ityp(na)) * &
                      SIN( angle1(ityp(na)) ) * COS( angle2(ityp(na)) )
        m_loc(2,na) = starting_magnetization(ityp(na)) * &
                      SIN( angle1(ityp(na)) ) * SIN( angle2(ityp(na)) )
        m_loc(3,na) = starting_magnetization(ityp(na)) * &
                      COS( angle1(ityp(na)) )
     END DO
  ENDIF
  !
  ! ... smallg_q flags in symmetry operations of the crystal
  ! ... that are not symmetry operations of the small group of q
  !
  ! TEMP: nsym0 contains the value of nsym for q=0
  nsym = nsym0
  sym(1:nsym)=.true.
  call smallg_q (xqq, modenum, at, bg, nsym, s, ftau, sym, minus_q)
  IF ( .not. time_reversal ) minus_q = .false.
  !
  ! ... for single-mode calculation: find symmetry operations 
  ! ... that leave the chosen mode unchanged. Note that array irt
  ! ... must be available: it is allocated and read from xml file 
  !
  if (modenum /= 0) then
     allocate(rtau (3, 48, nat))
     call sgam_ph (at, bg, nsym, s, irt, tau, rtau, nat, sym)
     call mode_group (modenum, xqq, at, bg, nat, nsym, s, irt, rtau, &
          sym, minus_q)
     deallocate (rtau)
  endif
  !
  ! Here we re-order all rotations in such a way that true sym.ops.
  ! are the first nsymq; rotations that are not sym.ops. follow
  !
  nsymq = copy_sym ( nsym, sym, s, sname, ftau, nat, irt, t_rev )
  !
  ! check if inversion (I) is a symmetry. If so, there should be nsymq/2
  ! symmetries without inversion, followed by nsymq/2 with inversion
  ! Since identity is always s(:,:,1), inversion should be s(:,:,1+nsymq/2)
  !
  invsym = ALL ( s(:,:,nsymq/2+1) == -s(:,:,1) )
  !
  CALL checkallsym( nsymq, s, nat, tau, ityp, at, &
          bg, nr1, nr2, nr3, irt, ftau, alat, omega )
  !
  ! ... Input k-points are assumed to be  given in the IBZ of the Bravais
  ! ... lattice, with the full point symmetry of the lattice.
  !
  nkstot = nks_start
  xk(:,1:nkstot) = xk_start(:,1:nkstot)
  wk(1:nkstot)   = wk_start(1:nkstot)
  !
  ! ... If some symmetries of the lattice are missing in the crystal,
  ! ... "irreducible_BZ" computes the missing k-points.
  !
  CALL irreducible_BZ (nrot, s, nsymq, at, bg, npk, nkstot, xk, wk, minus_q)
  ! TEMP: these two variables should be distinct
  nsym = nsymq
  !
  ! ... add k+q to the list of k
  !
  CALL set_kplusq( xk, wk, xqq, nkstot, npk )
  !
  IF ( lsda ) THEN
     !
     ! ... LSDA case: two different spin polarizations,
     ! ...            each with its own kpoints
     !
     if (nspin /= 2) call errore ('setup','nspin should be 2; check iosys',1)
     !
     CALL set_kup_and_kdw( xk, wk, isk, nkstot, npk )
     !
  ELSE IF ( noncolin ) THEN
     !
     ! ... noncolinear magnetism: potential and charge have dimension 4 (1+3)
     !
     if (nspin /= 4) call errore ('setup','nspin should be 4; check iosys',1)
     current_spin = 1
     !
  ELSE
     !
     ! ... LDA case: the two spin polarizations are identical
     !
     wk(1:nkstot)    = wk(1:nkstot) * degspin
     current_spin = 1
     !
     IF ( nspin /= 1 ) &
        CALL errore( 'setup', 'nspin should be 1; check iosys', 1 )
     !
  END IF
  !
  IF ( nkstot > npk ) CALL errore( 'setup', 'too many k points', nkstot )
  !
#ifdef __PARA
  !
  ! ... set the granularity for k-point distribution
  !
  IF ( ABS( xqq(1) ) < eps8 .AND. ABS( xqq(2) ) < eps8 .AND. &
       ABS( xqq(3) ) < eps8 ) THEN
     !
     kunit = 1
     !
  ELSE
     !
     kunit = 2
     !
  ENDIF
  !
  ! ... distribute k-points (and their weights and spin indices)
  !
  CALL divide_et_impera( xk, wk, isk, lsda, nkstot, nks )
  !
#else
  !
  nks = nkstot
  !
#endif
  !
  RETURN
  !
END SUBROUTINE setup_nscf
