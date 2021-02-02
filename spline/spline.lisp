;;;; cl-ana is a Common Lisp data analysis library.
;;;; Copyright 2021 Gary Hollis
;;;;
;;;; This file is part of cl-ana.
;;;;
;;;; cl-ana is free software: you can redistribute it and/or modify it
;;;; under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation, either version 3 of the License, or
;;;; (at your option) any later version.
;;;;
;;;; cl-ana is distributed in the hope that it will be useful, but
;;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU General Public License
;;;; along with cl-ana.  If not, see <http://www.gnu.org/licenses/>.
;;;;
;;;; You may contact Gary Hollis (me!) via email at
;;;; ghollisjr@gmail.com

(in-package :cl-ana.spline)

;; This project supports natural splines of any order, uniform and
;; non-uniform.

;;; Adding basic FFI for GSL's sparse matrix functions.
(defparameter +GSL-CONTINUE+ -2) ; from gsl_errno.h
(defparameter +GSL-SUCCESS+ 0) ; from gsl_errno.h

(defparameter +GSL-ITERSOLVE-GMRES+
  (cffi:foreign-symbol-pointer
   "gsl_splinalg_itersolve_gmres"))

(cffi:use-foreign-library gsll::libgsl)

;; Vectors
(cffi:defcfun "gsl_vector_alloc" :pointer
  (nelements :int))
(cffi:defcfun "gsl_vector_free" :void
  (vector :pointer))
(cffi:defcfun "gsl_vector_get" :double
  (vector :pointer)
  (i :int))
(cffi:defcfun "gsl_vector_set" :void
  (vector :pointer)
  (i :int)
  (x :double))
(cffi:defcfun "gsl_vector_ptr" :pointer
  (vector :pointer)
  (i :int))
(cffi:defcfun "gsl_vector_set_zero" :void
  (vector :pointer))
(cffi:defcfun "gsl_vector_set_all" :void
  (vector :pointer)
  (x :double))
(cffi:defcfun "gsl_vector_set_basis" :void
  (vector :pointer)
  (i :int))

;; Sparse Matrices
(cffi:defcfun "gsl_spmatrix_alloc" :pointer
  (nrows :unsigned-int)
  (ncols :unsigned-int))
(cffi:defcfun "gsl_spmatrix_free" :void
  (matrix :pointer))
(cffi:defcfun "gsl_spmatrix_get" :double
  (matrix :pointer)
  (i :int)
  (j :int))
(cffi:defcfun "gsl_spmatrix_set" :int
  (matrix :pointer)
  (i :int)
  (j :int)
  (x :double))
(cffi:defcfun "gsl_spmatrix_set_zero" :int
  (matrix :pointer)
  (i :int)
  (j :int))
(cffi:defcfun "gsl_spmatrix_ptr" :pointer
  (matrix :pointer)
  (i :int)
  (j :int))
;; compress matrix
(cffi:defcfun "gsl_spmatrix_ccs" :pointer
  (matrix :pointer))
;; Linear algebra
;; returns workspace
(cffi:defcfun "gsl_splinalg_itersolve_alloc" :pointer
  (type :pointer)
  (n :int)
  (m :int))
(cffi:defcfun "gsl_splinalg_itersolve_free" :void
  (workspace :pointer))
(cffi:defcfun "gsl_splinalg_itersolve_name" :pointer
  (workspace :pointer))
(cffi:defcfun "gsl_splinalg_itersolve_iterate" :int
  (sparse-matrix :pointer)
  (rhs-vector :pointer)
  (tolerance :double)
  (result-vector :pointer)
  (workspace :pointer))
(cffi:defcfun "gsl_splinalg_itersolve_normr" :double
  (workspace :pointer))

;; Utility/Helper Functions
(defun make-splinalg-workspace (nrows &optional (subspacerows 0))
  (gsl-splinalg-itersolve-alloc (cffi:mem-ref +GSL-ITERSOLVE-GMRES+
                                              :pointer 0)
                                nrows
                                subspacerows))

(defun sp-solve-system (coefs vector)
  (let* ((nrows (length coefs))
         (ncols (length (first coefs)))
         (mat (gsl-spmatrix-alloc nrows ncols))
         (vec (gsl-vector-alloc (length vector)))
         (w (make-splinalg-workspace nrows nrows))
         (tol 1d-3)
         (res (gsl-vector-alloc (length vector))))
    (loop
       for i from 0
       for row in coefs
       do
         (loop
            for j from 0
            for x in row
            when (not (zerop x))
            do (gsl-spmatrix-set mat i j x)))
    (loop
       for v in vector
       for i from 0
       do (gsl-vector-set vec i v))
    (let* ((m (gsl-spmatrix-ccs mat))
           (stat +GSL-CONTINUE+))
      (loop
         while (= stat +GSL-CONTINUE+)
         do (setf stat
                  (gsl-splinalg-itersolve-iterate m vec
                                                  tol
                                                  res
                                                  w))))
    (loop
       for i below (length vector)
       collecting (gsl-vector-get res i))))

(defstruct spline
  degree ;integer
  coefs ;2-D array
  xs ;vector
  deltas ;vector
  )

(defun spline-bin-index (xs x)
  "Returns integer index to spline bin"
  (loop
     for i from 0
     for xlow across xs
     when (>= xlow x)
     do (return (1- i))
     finally (return (1- (length xs)))))

(defun evaluate-natural-spline
    (spline x
     &key
       ;; set to T to maintain final value outside
       ;; domain.  Default is to have value 0
       ;; outside domain.
       continued-boundary-p)
  (with-slots (coefs deltas xs degree) spline
    (labels ((ev (index x)
               (polynomial (loop
                              for j to degree
                              collecting (aref coefs index j))
                           (/ (- x (aref xs index))
                              (aref deltas index)))))
      (let* ((index (spline-bin-index xs x)))
        (cond
          ((minusp index)
           (if continued-boundary-p
               (ev 0 (aref xs 0))
               0d0))
          ((> index (- (length xs) 2))
           (if continued-boundary-p
               (ev (- (length xs) 2)
                   (aref xs (1- (length xs))))
               0d0))
          (t
           (ev index x)))))))

(defun polynomial-derivative (params x degree)
  "Evaluates derivative of given degree of polynomial at point x."
  (polynomial (loop
                 for i from 0
                 for p in params
                 when (>= i degree)
                 collecting (* (npermutations i degree) p))
              x))

(defun polynomial-integral (params xlo xhi)
  "Evaluates definite integral of polynomial."
  (flet ((pint (x)
           (polynomial (cons 0d0
                             (loop
                                for i from 1d0
                                for p in params
                                collecting (/ p i)))
                       x)))
    (- (pint xhi) (pint xlo))))

(defun evaluate-natural-spline-derivative (spline x deg)
  (with-slots (coefs deltas xs degree) spline
    (labels ((ev (index x)
               (* (expt (aref deltas index) deg)
                  (polynomial-derivative
                   (loop
                      for j to degree
                      collecting (aref coefs index j))
                   (/ (- x (aref xs index))
                      (aref deltas index))
                   deg))))
      (let* ((index (spline-bin-index xs x)))
        (cond
          ((minusp index)
           0d0)
          ((> index (- (length xs) 2))
           0d0)
          (t
           (ev index x)))))))

(defun evaluate-natural-spline-integral (spline xlo xhi)
  "Evaluates definite integral of natural spline."
  (with-slots (xs deltas coefs degree) spline
    (labels ((binparams (xbin)
               (loop
                  for i to degree
                  collecting (aref coefs xbin i)))
             (wholebinint (xbin)
               (let* ((params (binparams xbin)))
                 (* (aref deltas xbin)
                    (polynomial-integral params 0d0 1d0)))))
      (let* ((N (1- (length xs)))
             (sign (cond
                     ((< xlo xhi)
                      1d0)
                     ((> xlo xhi)
                      -1d0)
                     (t 0d0)))
             (xlo (if (minusp sign)
                      xhi
                      xlo))
             (xhi (if (minusp sign)
                      xlo
                      xhi))
             ;; (x0 (elt xs 0))
             ;; (xN (elt xs (1- N)))
             (xlowbin
              (awhen (loop
                        for i from 0
                        for x across xs
                        when (>= x xlo)
                        do (return (1- i))
                        finally (return nil))
                (max it
                     0)))
             (xlowoffset (when xlowbin
                           (max (- xlo (aref xs xlowbin)) 0d0)))
             (xhighbin
              (awhen (loop
                        for i downfrom (- N 1) downto 0
                        for x = (aref xs i)
                        when (< x xhi)
                        do (return i)
                        finally (return nil))
                (min (- N 1)
                     it)))
             (xhighoffset (when xhighbin
                            (min (- xhi (aref xs xhighbin))
                                 (aref deltas (1- N)))))
             (lowparams (when xlowbin (binparams xlowbin)))
             (highparams (when xhighbin (binparams xhighbin))))
        (if (and xlowbin
                 xhighbin
                 (= xlowbin xhighbin))
            (* (aref deltas xlowbin)
               (polynomial-integral lowparams
                                    xlowoffset
                                    xhighoffset))
            (let* ((lowint
                    (when xlowbin
                      (* (aref deltas xlowbin)
                         (polynomial-integral lowparams
                                              (/ (- xlowoffset
                                                    (aref xs xlowbin))
                                                 (aref deltas xlowbin))
                                              1d0))))
                   (highint
                    (when xhighbin
                      (* (aref deltas xhighbin)
                         (polynomial-integral highparams
                                              0d0
                                              (/ xhighoffset
                                                 (aref deltas xhighbin)))))))
              (when (and lowint highint)
                (+ lowint
                   highint
                   (loop
                      for i
                      from (1+ xlowbin)
                      to (1- xhighbin)
                      summing
                        (wholebinint i))))))))))

(defun natural-spline (points
                       &key
                         (degree 3)
                         (tolerance 1d-5))
  (let* ((npoints (length points))
         (N (1- npoints))
         (nrows (* (1+ degree) N))
         (coefs (gsl-spmatrix-alloc nrows
                                    nrows))
         (vec (gsl-vector-alloc (* (1+ degree) N)))
         (equation-index 0)
         (xs (coerce (cars points) 'vector))
         (ys (coerce (cdrs points) 'vector))
         (deltas (- (subseq xs 1) xs))
         (w (make-splinalg-workspace nrows nrows))
         (tol (->double-float tolerance))
         (res (gsl-vector-alloc nrows))
         (sp (make-spline :coefs (make-array (list N (1+ degree)))
                          :degree degree
                          :xs xs
                          :deltas deltas)))
    ;;; coefficients matrix
    ;;;
    ;;; Five constraint types:
    ;;; 1. Left boundaries.
    ;;; 2. Right boundaries.
    ;;; 3. Continuity.
    ;;; 4. Left natural derivatives.
    ;;; 5. Right natural derivatives.

    ;; 1. Left boundaries.
    (loop
       for i below N
       for j = (* (1+ degree) i)
       do
       ;; coefs
         (gsl-spmatrix-set coefs i j
                           1d0)
       ;; vector
         (gsl-vector-set vec i (->double-float (aref ys i))))
    (incf equation-index N)
    ;; 2. Right boundaries
    (loop
       for i below N
       for ii = (+ equation-index i)
       do
       ;; coefs
         (loop
            for j to degree
            for jj = (+ j (* (1+ degree) i))
            do (gsl-spmatrix-set coefs ii jj
                                 1d0))
       ;; vector
         (gsl-vector-set vec ii
                         (->double-float
                          (aref ys (1+ i)))))
    (incf equation-index N)
    ;; Continuity
    (loop
       for L from 1 below degree ; degree-1 fold
       do
         (loop
            for i below (1- N)
            for ii = (+ equation-index
                        (* (- L 1) (1- N))
                        i)
            do
            ;; coefs
            ;; rhs
              (gsl-spmatrix-set coefs ii (+ (* (1+ degree)
                                               (1+ i))
                                            L)
                                -1d0)
            ;; lhs
              (loop
                 for j from L to degree
                 for jj = (+ (* (1+ degree)
                                i)
                             j)
                 do (gsl-spmatrix-set coefs ii jj
                                      (->double-float
                                       (* (binomial j L)
                                          (expt (/ (aref deltas (1+ i))
                                                   (aref deltas i))
                                                L)))))
            ;; vec
              (gsl-vector-set vec ii 0d0)))
    (incf equation-index (* (1- degree) (1- N)))
    ;; natural derivatives
    (cond
      ((= degree 2)
       (gsl-spmatrix-set coefs
                         equation-index
                         2
                         1d0)
       ;; vec
       (gsl-vector-set vec equation-index 0d0))
      (t
       (let* ((leftstart (if (evenp degree)
                             (floor degree 2)
                             (floor (+ degree 1) 2)))
              (rightstart (if (evenp degree)
                              (+ (floor degree 2) 1)
                              (floor (+ degree 1) 2))))
         ;; 4. left
         (loop
            for i from 0
            for L from leftstart below degree
            for ii = (+ equation-index i)
            do
            ;; coefs
              (gsl-spmatrix-set coefs
                                ii
                                L
                                1d0)
            ;; vec
              (gsl-vector-set vec ii 0d0))
         (incf equation-index (- degree leftstart))
         ;; 5. right
         (loop
            for i from 0
            for L from rightstart below degree
            for ii = (+ equation-index i)
            do
            ;; coefs
              (loop
                 for j from L to degree
                 for jj = (+ j
                             (* (1+ degree)
                                (- npoints 2)))
                 do
                   (gsl-spmatrix-set coefs ii jj
                                     (->double-float
                                      (npermutations j L))))
            ;; vec
              (gsl-vector-set vec ii 0d0)))))
    ;; solve
    (let* ((m (gsl-spmatrix-ccs coefs))
           (stat +GSL-CONTINUE+))
      (loop
         while (= stat +GSL-CONTINUE+)
         do (setf stat
                  (gsl-splinalg-itersolve-iterate
                   m vec
                   tol res
                   w)))
      (loop
         for i below nrows
         for ii = (floor i (1+ degree))
         for jj = (mod i (1+ degree))
         do (setf (aref (spline-coefs sp) ii jj)
                  (gsl-vector-get res i)))
      ;; cleanup
      (gsl-spmatrix-free m)
      (gsl-spmatrix-free coefs)
      (gsl-vector-free vec)
      (gsl-vector-free res)
      (gsl-splinalg-itersolve-free w))
    (values (lambda (x)
              (evaluate-natural-spline sp x))
            sp)))

(defun gsl-spline (points
                   &key (type gsll:+cubic-spline-interpolation+))
  "Returns a Lisp function which returns the spline interpolation of
these points using GSLL.  Defaults to a cubic spline.

Returns 0 outside of the original domain since GSLL croaks outside of
it for at least the cubic spline."
  (let* ((points (sort (copy-list points)
                       #'<
                       :key #'car))
         (xmin (minimum (cars points)))
         (xmax (maximum (cars points)))
         (xs (grid:make-foreign-array 'double-float
                                      :initial-contents
                                      (cars points)))

         (ys (grid:make-foreign-array 'double-float
                                      :initial-contents
                                      (cdrs points)))
         (spline
          (gsll:make-spline type xs ys)))
    (values (lambda (x)
              (if (not (<= xmin x xmax))
                  0d0
                  (gsll:evaluate spline x)))
            spline)))
