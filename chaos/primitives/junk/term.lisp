;;;-*-Mode:LISP; Package: Chaos; Base:10; Syntax:Common-lisp -*-
;;;
;;; Copyright (c) 2000-2015, Toshimi Sawada. All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;   * Redistributions of source code must retain the above copyright
;;;     notice, this list of conditions and the following disclaimer.
;;;
;;;   * Redistributions in binary form must reproduce the above
;;;     copyright notice, this list of conditions and the following
;;;     disclaimer in the documentation and/or other materials
;;;     provided with the distribution.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
;;; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;
(in-package :chaos)
#|==============================================================================
				 System: Chaos
			   Module: primitives.chaos
				File: term.lisp
==============================================================================|#
#-:chaos-debug
(declaim (optimize (speed 3) (safety 0) #-GCL (debug 0)))
#+:chaos-debug
(declaim (optimize (speed 1) (safety 3) #-GCL (debug 3)))

;;;**********
;;; TERM CELL
;;;*****************************************************************************
;;; <TERM> ::= <Variable> | <ApplForm > | <SimpleLispForm> | <PsuedoVariable>
;;;            <GeneralLispForm> | <BuiltInConstant> | <SystemObject>
;;;
;;; Implementation:
;;; ( . )
;;;   |
;;;   V
;;; <TermBody>
;;;*****************************************************************************

;;; TYPE -----------------------------------------------------------------------
(deftype term () 'cons)

;;; accessor ___________________________________________________________________
(defmacro term-body (_term) `(car ,_term))

;;; constructor
(defmacro create-term (obj) `(list ,obj))

#||
;;; term pool __________________________________________________________________
(defvar alloc-count)
(defvar .term-cell-pool. nil)		; for term cell
(defvar .term-body-pool. nil)		; for term body
(defconstant .allocation-step. 1024)

(defun chaos-allocate-more-cell (num)
  (incf alloc-count)
  (dotimes-fixnum (x num) (push (list nil) .term-cell-pool.)))

(defun chaos-allocate-more-body (num)
  (dotimes-fixnum (x num) (push (make-list 4) .term-body-pool.)))

;;; initialization
(eval-when (eval load)
  (setq alloc-count 0)
  (setq .term-cell-pool. nil)
  (setq .term-body-pool. nil)
  (chaos-allocate-more-cell .allocation-step.)
  (chaos-allocate-more-body .allocation-step.))

;;; allocator
(defmacro allocate-chaos-term-cell ()
  ` (if .term-cell-pool. (pop .term-cell-pool.)
	(progn
	  (chaos-allocate-more-cell .allocation-step.)
	  (pop .term-cell-pool.))))

(defmacro allocate-chaos-term-body ()
  ` (if .term-body-pool. (pop .term-body-pool.)
	(progn
	  (chaos-allocate-more-body .allocation-step.)
	  (pop .term-body-pool.))))

;;; deallocator
;;; setf nil to give a change to GC.
(defmacro deallocate-chaos-term-cell (cell)
  `(progn (setf (term-body ,cell) nil) (push ,cell .term-cell-pool.)))
(defmacro deallocate-chaos-term-body (body) `(push ,body .term-body-pool.))

(defun deallocate-whole-term (cell)
  (deallocate-chaos-term-body (term-body cell))
  (deallocate-chaos-term-cell cell))

||#

;;; term-eq : term1 term2 -> bool ______________________________________________
;;; returns t iff "term1" and "term2" are exactly the same object.
;;;
(defmacro term-eq (*t1 *t2) `(eq (term-body ,*t1) (term-body ,*t2)))
(defmacro term-equal (*t1 *t2) `(equal ,*t1 ,*t2))

;;; term-replace : from to -> from' ____________________________________________
;;; term1 is modified so that its body becomes a body of term to.
;;;
(defmacro term-replace (*from *to) `(setf (term-body ,*from) (term-body ,*to)))

;;;****************************
;;; GENERAL TERM BODY STRUCTURE
;;;****************************
;;; - encoded terms ************************************************************
;;; ( term-code encoded-term-contents )
;;; 1. variable
;;;    encoded-term-contents ::= variable-code sort-m-code
;;; 2. application-form
;;;    encoded-term-contents ::= operator-code sort-id-bit subterms
;;; 3. lisp-code
;;;    encoded-term-contents ::= lisp-function sort-id-bit
;;; 4. builtin-constant
;;;    encoded-term-contents ::= builtin-value sort-id-bit
;;; 5. system-object
;;;    encoded-term-contents ::= object-value  sort-id-bit
;;; 6. psuedo-variable
;;;    encoded-term-contents ::= variable-code sort-id-bit
;;;
;;; - decoded (pre encoded) terms *********************************************
;;; ( term-code pre-encoded-term-content )
;;; 1. variable
;;;    pre-encoded-term-contents ::= variable-name sort
;;; 2. application-form
;;;    pre-encoded-term-contents ::= method sort subterms
;;; 3. lisp-code
;;;    pre-encoded-term-contents ::= lisp-function sort orignal-form
;;; 4. builtin-constant
;;;    pre-encoded-term-contents ::= builtin-value sort
;;; 5. system-object
;;;    pre-encoded-term-contents ::= object-value sort
;;; 6. psuedo-variable
;;;    pre-encoded-term-contents ::= variable-name sort
;;;

;;;-----------------------------------------------------------------------------
;;; TERM-CODE Values : fixnum (16bits)
;;;----------------------------------------------------------------------------- 

;;; TERM-CODE PART is a 16bits fixnum coded flags:
;;; lower 12 bits : kind (variable, application form, etc.)
;;; higher 4 bits : status (reduced, lowest parsed, on demamd)

;;; LOWER 12 bits **************************************************************
;;; represents kids:
;;; #x001 : variable
;;; #x002 : application form 
;;; #x004 : simple lisp code
;;; #x008 : general lisp code
;;; #x010 : psuedo constant bit
;;; #x030 : builtin constant
;;; #x040 : system object

;;;
;;; #x101 : decoded variable
;;; #x102 : decoded application term
;;; #x104 : decoded simple lisp code
;;; #x108 : decoded general lisp code
;;; #x110 : decoded psuedo constant
;;; #x130 : decoded builtin constant
;;; #x140 : decoded system object

(defconstant variable-type #x001)
(defconstant application-form-type #x002)
(defconstant simple-lisp-code-type #x004)
(defconstant general-lisp-code-type #x008)
(defconstant lisp-code-type (logior simple-lisp-code-type general-lisp-code-type))
(defconstant psuedo-constant-type #x010)
(defconstant pure-builtin-constant-type #x020)
(defconstant builtin-constant-type (logior psuedo-constant-type
					   pure-builtin-constant-type))
(defconstant system-object-type #x040)

(defconstant pre-encode-bit #x100)
(defconstant pre-variable-type (logior pre-encode-bit variable-type))
(defconstant pre-application-form-type (logior pre-encode-bit
					       application-form-type))
(defconstant pre-simple-lisp-code-type (logior pre-encode-bit
					       simple-lisp-code-type))
(defconstant pre-general-lisp-code-type (logior pre-encode-bit
						general-lisp-code-type))
(defconstant pre-lisp-code-type (logior pre-encode-bit lisp-code-type))
(defconstant pre-psuedo-constant-type
  (logior pre-encode-bit psuedo-constant-type))
(defconstant pre-builtin-constant-type (logior pre-encode-bit
					       builtin-constant-type))
(defconstant pre-pure-builtin-constant-type
  (logior pre-encode-bit pure-builtin-constant-type))
(defconstant pre-system-object-type (logior pre-encode-bit system-object-type))

;;; HIGHER 4 bits *************************************************************
;;; represents state:
;;; #x1000 : reduced flag       : on iff the term is reduced.
;;; #x2000 : lowest parsed flag : on iff the term is lowest parsed.
;;; #x4000 : on demand flag     : on iff the term is on deman.
;;; #x8000 : not used

(defconstant reduced-flag #x1000)
(defconstant lowest-parsed-flag #x2000)
(defconstant on-demand-flag #x4000)

;;; ********************************
;;; GENERAL TERM STRUCTURE ACCESSORS *******************************************
;;;*********************************

;;; ******************
;;; ACCESS BY POSITION ---------------------------------------------------------
;;; ******************
;;; VIA BODY DIRECTLY
(defmacro body-1st (*o) `(car ,*o))
(defmacro body-2nd (*o) `(cadr ,*o))
(defmacro body-3rd (*o) `(caddr ,*o))
(defmacro body-4th (*o) `(cadddr ,*o))

;;; VIA TERM CELL
(defmacro term-1st (*o) `(caar ,*o))
(defmacro term-2nd (*o) `(cadar ,*o))
(defmacro term-3rd (*o) `(caddar ,*o))
(defmacro term-4th (*o) `(cadddr (car ,*o)))

;;; *************
;;; ACCES BY NAME ______________________________________________________________
;;; *************

;;;-----------------------------------------------------------------------------
;;; CODE : the 1st part
;;;-----------------------------------------------------------------------------
;;; from body
(defmacro term$code (*term-body) `(the fixnum (body-1st ,*term-body)))
;;; from term
(defmacro term-code (*term) `(the fixnum (term-1st ,*term)))

;;;-----------------------------------------------------------------------------
;;; SORT/SORT-CODE : the 3rd part
;;;-----------------------------------------------------------------------------
;;; from body
(defmacro term$sort (*term-body) `(the sort (body-3rd ,*term-body)))
(defmacro term$sort-code (*term-body) `(the fixnum (body-3rd ,*term-body)))
;;; from term
(defmacro term-sort (*term) `(the sort (term-3rd ,*term)))
(defmacro term-sort-code (*term) `(the fixnum (term-3rd ,*term)))

(defmacro variable$sort (*term-body) `(the sort (body-3rd ,*term-body)))
(defmacro variable-sort (*term-body) `(the sort (term-3rd ,*term-body)))

;;;-----------------------------------------------------------------------------
;;; THE 2nd part
;;; varies for each types:
;;; (1) application form : op-code or method
;;; (2) builtin constant : builtin value
;;; (3) lisp form        : lisp function
;;; (4) variable         : variable-code or variable name
;;; (5) psuedo constant  : constant-code or variable name
;;; (6) system object    : object
;;;-----------------------------------------------------------------------------

;;; APPLICATION FORM :

(defmacro term$op-code (_term-body) `(body-2nd ,_term-body))
(defmacro term$method (_term-body) `(the method (body-2nd ,_term-body)))
(defmacro term$head (_term-body) `(the method (body-2nd ,_term-body)))
(defmacro term-op-code (_term) `(term-2nd ,_term))
(defmacro term-method (_term) `(the method (term-2nd ,_term)))
(defmacro term-head (_term) `(the method (term-2nd ,_term)))

(defmacro change$head-operator (_body _op)
  `(setf (body-2nd ,_body) ,_op))
(defmacro change-head-operator (_term _op)
  `(setf (term-2nd ,_term) ,_op))

;;; VARIABLE TERM :

(defmacro term$variable-code (_term-body) `(body-2nd ,_term-body))
(defmacro variable$name (_term-body) `(body-2nd ,_term-body))
(defmacro term-variable-code (_term) `(term-2nd ,_term))
(defmacro variable-name (_term) `(cadar ,_term))

;;; BUILTIN CONSTANT :

(defmacro term$builtin-value (_term-body) `(body-2nd ,_term-body))
(defmacro term-builtin-value (_term) `(term-2nd ,_term))

;;; PSUEDO-CONSTANT
;;; just the same as BUILTIN CONSTANT
(defmacro term$psuedo-constant-code (_term-body) `(body-2nd ,_term-body))
(defmacro term$psuedo-constant-name (_term-body) `(body-2nd ,_term-body))
(defmacro psuedo-constant-code (_term) `(term-2nd ,_term))
(defmacro psuedo-constant-name (_term) `(term-2nd ,_term))

;;; LISP FORM :

(defmacro term$lisp-function (_term-body) `(body-2nd ,_term-body))
(defmacro term-lisp-function (_term) `(term-2nd ,_term))
(defmacro lisp-form-function (_term) `(term-2nd ,_term)) ; synonym


;;; SYSTEM OBJECT :

(defmacro term$system-object (_term-body) `(body-2nd ,_term-body))
(defmacro term-system-object (_term) `(term-2nd ,_term))

;;;-----------------------------------------------------------------------------
;;; THE REST PART
;;;
;;; (term-type {opcode | builtin-value | lisp-function} sort-code rest)
;;;     1                       2                           3      4
;;; the rest part of a term (term-type sort-code rest)
;;;  term type           : contents
;;;  ==========================================================================
;;;  lisp-code           : rest = orignal-form
;;;                                  4
;;;  application-form    : rest = subterms
;;;                                  4
;;;-----------------------------------------------------------------------------
;;; LISP FORM :
;;; setf'able
(defmacro term$lisp-code-original-form (_term-body)
  `(body-4th ,_term-body))
(defmacro term$lisp-form-original-form (_term-body)
  `(body-4th ,_term-body))		; synonym
(defmacro lisp-code-original-form (_term)
  `(term-4th ,_term))
(defmacro lisp-form-original-form (_term)
  `(term-4th ,_term))			; synonym

;;; APPLICATION FORM :
;;; all are setf'able
(defmacro term$subterms (_term-body) `(the list (body-4th ,_term-body)))
(defmacro term-subterms (_term) (the list `(term-4th ,_term)))

;;; subterm accessors
(defmacro term$arg-1 (_term-body) `(car (term$subterms ,_term-body)))
(defmacro term$arg-2 (_term-body) `(cadr (term$subterms ,_term-body)))
(defmacro term$arg-3 (_term-body) `(caddr (term$subterms ,_term-body)))
(defmacro term$arg-4 (_term-body) `(cadddr (term$subterms ,_term-body)))
(defmacro term$arg-n (_term-body n)
  ` (the term
      (nth (the fixnum ,n) (term$subterms ,_term-body))))

(defmacro term-arg-1 (_term) `(car (term-subterms ,_term)))
(defmacro term-arg-2 (_term) `(cadr (term-subterms ,_term)))
(defmacro term-arg-3 (_term) `(caddr (term-subterms ,_term)))
(defmacro term-arg-4 (_term) `(cadddr (term-subterms ,_term)))
(defmacro term-arg-n (_term n)
  ` (the term (nth (the fixnum ,n)
		   (term-subterms ,_term))))

;;; *****************
;;; term type testers___________________________________________________________
;;; *****************

;;; check from term type.

(defmacro term-code$is-decoded? (_term-code)
  `(test-and pre-encode-bit ,_term-code))

;;; *note* : the following predicate does not get be affected by
;;;          pre-endcode bit.

(defmacro term-code$is-variable? (_term-code)
  `(test-and ,_term-code variable-type))
(defmacro term-code$is-application-form? (_term-code)
  `(test-and ,_term-code application-form-type))
(defmacro term-code$is-lisp-code? (_term-code)
  `(test-and ,_term-code lisp-code-type))
(defmacro term-code$is-simple-lisp-code? (_term-code)
  `(test-and ,_term-code simple-lisp-code-type))
(defmacro term-code$is-general-lisp-code? (_term-code)
  `(test-and ,_term-code general-lisp-code-type))
(defmacro term-code$is-builtin-constant? (_term-code)
  `(test-and ,_term-code builtin-constant-type))
(defmacro term-code$is-pure-builtin-constant? (_term-code)
  `(test-and ,_term-code pure-builtin-constant-type))
(defmacro term-code$is-psuedo-constant? (_term-code)
  `(test-and ,_term-code psuedo-constant-type))
(defmacro term-code$is-system-object? (_term-code)
  `(test-and ,_term-code system-object-type))
    
;;; test via body directly

(defmacro term$is-variable? (_term-body)
  `(term-code$is-variable? (term$code ,_term-body)))
(defmacro term$is-application-form? (_term-body)
  `(term-code$is-application-form? (term$code ,_term-body)))
(defmacro term$is-applform? (_term-body)
  `(term-code$is-application-form? (term$code ,_term-body)))
(defmacro term$is-lisp-code? (_term-body)
  `(term-code$is-lisp-code? (term$code ,_term-body)))
(defmacro term$is-lisp-form? (_term-body)
  `(term-code$is-lisp-code? (term$code ,_term-body)))
(defmacro term$is-simple-lisp-code? (_term-body)
  `(term-code$is-simple-lisp-code? (term$code ,_term-body)))
(defmacro term$is-simple-lisp-form? (_term-body)
  `(term-code$is-simple-lisp-code? (term$code ,_term-body)))
(defmacro term$is-general-lisp-code? (_term-body)
  `(term-code$is-general-lisp-code? (term$code ,_term-body)))
(defmacro term$is-general-lisp-form? (_term-body)
  `(term-code$is-general-lisp-code? (term$code ,_term-body)))
(defmacro term$is-pure-builtin-constant? (_term-body)
  `(term-code$is-pure-builtin-constant? (term$code ,_term-body)))
(defmacro term$is-builtin-constant? (_term-body)
  `(term-code$is-builtin-constant? (term$code ,_term-body)))
(defmacro term$is-psuedo-constant? (_term-body)
  `(term-code$is-psuedo-constant? (term$code ,_term-body)))
(defmacro term$is-system-object? (_term-body)
  `(term-code$is-system-object? (term$code ,_term-body)))

;;; test via term cell

(defmacro term-is-variable? (_term)
  `(term-code$is-variable? (term-code ,_term)))
(defmacro term-is-application-form? (_term)
  `(term-code$is-application-form? (term-code ,_term)))
(defmacro term-is-applform? (_term)
  `(term-code$is-application-form? (term-code ,_term)))
(defmacro term-is-lisp-form? (_term)
  `(term-code$is-lisp-code? (term-code ,_term)))
(defmacro term-is-simple-lisp-form? (_term)
  `(term-code$is-simple-lisp-code? (term-code ,_term)))
(defmacro term-is-general-lisp-form? (_term)
  `(term-code$is-general-lisp-code? (term-code ,_term)))
(defmacro term-is-pure-builtin-constant? (_term)
  `(term-code$is-pure-builtin-constant? (term-code ,_term)))
(defmacro term-is-builtin-constant? (_term)
  `(term-code$is-builtin-constant? (term-code ,_term)))
(defmacro term-is-psuedo-constant? (_term)
  `(term-code$is-psuedo-constant? (term-code ,_term)))
(defmacro term-is-system-object? (_term)
  `(term-code$is-system-object? (term-code ,_term)))

;;; ******************
;;; TERM STATE TESTERS _________________________________________________________
;;;   and SETTERS      
;;; ******************

;;; just a synonym of term$code, term-code
(defmacro term$state-flag (__term-body) `(body-1st ,__term-body))
(defmacro term-state-flag (__term) `(term-1st ,__term))

;;;; STATE TESTERS

;;; reduced flag

(defmacro term$test-reduced-flag (*term-body)
  `(test-and reduced-flag (term$state-flag ,*term-body)))
(defmacro term-test-reduced-flag (*term)
  `(test-and reduced-flag (term-state-flag ,*term)))
(defmacro term-is-reduced? (_term)	; synonym
  `(term-test-reduced-flag ,_term))

;;; lowest parsed flag

(defmacro term$test-lowest-parsed-flag (*term-body)
  `(test-and lowest-parsed-flag (term$state-flag ,*term-body)))
(defmacro term-test-lowest-parsed-flag (*term)
  `(test-and lowest-parsed-flag (term-state-flag ,*term)))
(defmacro term-is-lowest-parsed? (_term)	; synonym
  `(term-test-lowest-parsed-flag ,_term))

;;; on demand flag

(defmacro term$test-on-demand-flag (*term-body)
  `(test-and on-demand-flag (term$state-flag ,*term-body)))
(defmacro term-test-on-demand-flag (*term)
  `(test-and on-demand-flag (term-state-flag ,*term)))
(defmacro term-is-on-demand? (_term)	; synonym
  `(term-test-on-demand-flag ,_term))

;;; STATE SETTERS

;;; reduced flag :
(defmacro term$set-reduced-flag (*term-body)
  (once-only (*term-body)
    `(setf (term$state-flag ,*term-body)
           (make-or reduced-flag (term$state-flag ,*term-body)))))
(defmacro term-set-reduced-flag (*term)
  (once-only (*term)
    `(setf (term-state-flag ,*term)
           (make-or reduced-flag (term-state-flag ,*term)))))
(defmacro mark-term-as-reduced (_term)	; synonym
  `(term-set-reduced-flag ,_term))

(defconstant .not-reduced-bit. (logand #xffff (lognot reduced-flag)))

(defmacro term$unset-reduced-flag (*term-body)
  (once-only (*term-body)
    `(setf (term$state-flag ,*term-body)
           (make-and .not-reduced-bit. (term$state-flag ,*term-body)))))

(defmacro term-unset-reduced-flag (*term)
  (once-only (*term)
    `(setf (term-state-flag ,*term)
           (make-and .not-reduced-bit. (term-state-flag ,*term)))))
(defmacro mark-term-as-not-reduced (_term) ; synonym
  `(term-unset-reduced-flag ,_term))

;;; lowest parsed flag :

(defmacro term$set-lowest-parsed-flag (*term-body)
  (once-only (*term-body)
    `(setf (term$state-flag ,*term-body)
           (make-or lowest-parsed-flag 
	            (term$state-flag ,*term-body)))))

(defmacro term-set-lowest-parsed-flag (*term)
  (once-only (*term)
    `(setf (term-state-flag ,*term)
           (make-or lowest-parsed-flag
	            (term-state-flag ,*term)))))

(defmacro mark-term-as-lowest-parsed (_term)	; synonym
  `(term-set-lowest-parsed-flag ,_term))

(defconstant .not-lowest-parsed-bit. (logand #xffff (lognot lowest-parsed-flag)))

(defmacro term$unset-lowest-parsed-flag (*term-body)
  (once-only (*term-body)
    `(setf (term$state-flag ,*term-body)
           (make-and .not-lowest-parsed-bit.
                     (term$state-flag ,*term-body)))))

(defmacro term-unset-lowest-parsed-flag (*term)
  (once-only (*term)
    `(setf (term-state-flag ,*term)
           (make-and .not-lowest-parsed-bit.
	             (term-state-flag ,*term)))))

(defmacro mark-term-as-not-lowest-parsed (_term)	; synonym
  `(term-unset-lowest-parsed-flag ,_term))

;;; on demand flag :

(defmacro term$set-on-demand-flag (*term-body)
  (once-only (*term-body)
   `(setf (term$state-flag ,*term-body)
          (make-or on-demand-flag
	           (term$state-flag ,*term-body)))))

(defmacro term-set-on-demand-flag (*term)
  (once-only (*term)
    `(setf (term-state-flag ,*term)
           (make-or on-demand-flag
	            (term-state-flag ,*term)))))

(defmacro mark-term-as-on-demand (_term)	; synonym
  `(term-set-on-demand-flag ,_term))

(defconstant .not-on-demand-bit. (logand #xffff (lognot on-demand-flag)))

(defmacro term$unset-on-demand-flag (*term-body)
  (once-only (*term-body)
   `(setf (term$state-flag ,*term-body)
          (make-and .not-on-demand-bit.
	           (term$state-flag ,*term-body)))))

(defmacro term-unset-on-demand-flag (*term)
  (once-only (*term)
    `(setf (term-state-flag ,*term)
           (make-and .not-on-demand-bit.
	             (term-state-flag ,*term)))))

(defmacro mark-term-as-not-on-demand (_term) ; synonym
  `(term-unset-on-demand-flag ,_term))

;;;*****************************************************************************
;;; TERM CONSTUCTORS
;;;*****************************************************************************

;;; constructors for pre-encoded version precedes `@'.

;;; ********
;;; VARIABLE ___________________________________________________________________
;;; ********

;;; *NOTE* variables are always considered as reduced.
;;;        lowest parsed flag is also set to on.

(defconstant var-const-code
  (logior variable-type reduced-flag lowest-parsed-flag))
(defconstant pre-var-const-code
  (logior var-const-code pre-encode-bit))

#||
(defmacro create-variable-term (variable-code sort-m-code)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) var-const-code
	    (variable$code __body) ,variable-code
	    (variable$sort __body) ,sort-m-code
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

(defmacro @create-variable-term (variable-name sort)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) pre-var-const-code
	    (variable$name __body) ,variable-name
	    (variable$sort __body) ,sort
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

||#

(defmacro create-variable-term (_variable-code _sort-m-code)
  ` (create-term (list var-const-code ,_variable-code ,_sort-m-code)))

(defmacro @create-variable-term (__variable-name __sort)
  ` (create-term (list pre-var-const-code ,__variable-name ,__sort)))

(defmacro make-variable-term (__sort __variable-name) ; synonym
  `(create-term (list pre-var-const-code ,__variable-name ,__sort)))

(defmacro variable-copy (var)
  (once-only (var)
    `(@create-variable-term (variable-name ,var) (variable-sort ,var))))


;;; ****************
;;; APPLICATION-FORM ___________________________________________________________
;;; ****************

#||
(defmacro create-application-form-term (operator-code sort-id-code subterms)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) application-form-type
	    (term$op-code __body) ,operator-code
	    (term$sort-code __body) ,sort-id-code
	    (term$subterms __body) ,subterms
	    (term-body __cell) __body)
      __cell))

(defmacro @create-application-form-term (method sort subterms)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) pre-application-form-type
	    (term$head __body) ,method
	    (term$sort __body) ,sort
	    (term$subterms __body) ,subterms
	    (term-body __cell) __body)
      __cell))

||#
(defmacro create-application-form-term (_operator-code _sort-id-code _subterms)
  `(create-term (list applicatin-form-type ,_operator-code ,_sort-id-code ,_subterms)))

(defmacro @create-application-form-term (_method _sort _subterms)
  `(create-term (list pre-application-form-type ,_method ,_sort ,_subterms)))

;;; ****************
;;; SIMPLE-LISP-CODE ___________________________________________________________
;;; ****************

;;; *NOTE* simple-lisp-code is always treated as reduced and lowest parsed.
;;;
(defconstant simple-lisp-const-code
  (logior reduced-flag lowest-parsed-flag simple-lisp-code-type))
(defconstant pre-simple-lisp-const-code
  (logior pre-encode-bit simple-lisp-const-code))

#||
(defmacro create-simple-lisp-code-term (function &optional sort-id-code)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) simple-lisp-const-code
	    (term$lisp-function __body) ,function
	    (term$sort-code __body) ,sort-id-code
	    (term-body __cell) __body)
      __cell))

(defmacro @create-simple-lisp-code-term (function original-form sort)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) pre-simple-lisp-const-code
	    (term$lisp-function __body) ,function
	    (term$lisp-code-original-form __body) ,original-form
	    (term$sort __body) ,sort
	    (term-body __cell) __body)
      __cell))

||#
(defmacro create-simple-lisp-code-term (_function &optional _sort-id-code)
  `(create-term (list simple-lisp-const-code ,_function ,_sort-id-code nil)))

(defmacro @create-simple-lisp-code-term (_function &optional _sort)
  `(create-term (list pre-simple-lisp-const-code ,_function ,_sort nil)))

(defmacro make-simple-lisp-form-term (__original-form)
  `(create-term (list pre-simple-lisp-const-code nil *cosmos* ,__original-form)))
    
;;; *****************
;;; GENERAL-LISP-CODE __________________________________________________________
;;; *****************

;;; *NOTE* general-lisp-code is always treated as reduced and lowest parsed.
;;;
(defconstant general-lisp-const-code
  (logior reduced-flag lowest-parsed-flag general-lisp-code-type))
(defconstant pre-general-lisp-const-code
  (logior pre-encode-bit general-lisp-const-code))

#||
(defmacro create-general-lisp-code-term (function sort-id-code)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) general-lisp-const-code
	    (term$lisp-function __body) ,function
	    (term$sort-code __body) ,sort-id-code
	    (term-body __cell) __body)
      __cell))

(defmacro @create-general-lisp-code-term (function original-form sort)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) pre-general-lisp-const-code
	    (term$lisp-function __body) ,function
	    (term$sort __body) ,sort
	    (term$lisp-code-original-form __body) ,original-form
	    (term-body __cell) __body)
      __cell))

||#

(defmacro create-general-lisp-code-term (_function _sort-id-code)
  `(create-term (list general-lisp-const-code ,_function ,_sort-id-code nil)))

(defmacro @create-general-lisp-code-term (_function _original-form _sort)
  `(create-term (list pre-general-lisp-const-code ,_function ,_sort ,_original-form)))

(defmacro make-general-lisp-form-term (_original-form)
  `(create-term (list pre-general-lisp-const-code nil *cosmos* ,_original-form)))

;;; ****************
;;; BUILTIN CONSTANT ___________________________________________________________
;;; ****************

;;; For a while, builtin constant terms cannot be rewritten,i.e.,
;;; they are treated as irreducible. so we set flag reduced, always.
(defconstant builtin-constr-code
  (logior pure-builtin-constant-type reduced-flag))
(defconstant pre-builtin-constr-code
  (logior pre-encode-bit builtin-constr-code))

#||
(defmacro create-builtin-constant-term (value sort-id-code)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) builtin-constr-code
	    (term$builtin-value __body) ,value
	    (term$sort-code __body) ,sort-id-code
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

(defmacro @create-builtin-constant-term (value sort)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) pre-builtin-constr-code
	    (term$builtin-value __body) ,value
	    (term$sort __body) ,sort
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

||#
;;; downward compatibility
(defmacro make-bconst-term (_sort_ _value_)
  `(create-term (list pre-builtin-constr-code ,_value_ ,_sort_)))

;;; ***************
;;; PSUEDO CONSTANT____________________________________________________________
;;; ***************

;;; *NOTE* psuedo constant is treated as reduced and lowest parsed.
(defconstant psuedo-constant-const-code
  (logior reduced-flag lowest-parsed-flag psuedo-constant-type))
(defconstant pre-psuedo-constant-const-code
  (logior pre-encode-bit psuedo-constant-const-code))

#||
(defmacro create-psuedo-constant-term (var-code sort-id-code)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) psuedo-constant-const-code
	    (term$psuedo-constant-code __body) ,var-code
	    (term$sort-code __body) ,sort-id-code
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

(defmacro @create-psuedo-constant-term (name sort)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) pre-psuedo-constant-const-code
	    (term$psuedo-constant-name __body) ,name
	    (term$sort __body) ,sort
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

||#
;;; downward compat.
(defmacro make-psuedo-constant-term (_sort _name)
  `(create-term (list pre-psuedo-constant-const-code ,_name ,_sort)))

(defmacro make-pvariable-term (_sort _name)
  `(create-term (list pre-psuedo-constant-const-code ,_name ,_sort)))

;;; *************
;;; SYSTEM OBJECT ____________________________________________________________
;;; *************

;;; *NOTE* system object is treated as reduced and lowest parsed.
(defconstant system-object-const-code
  (logior reduced-flag lowest-parsed-flag system-object-type))
(defconstant pre-system-object-const-code
  (logior pre-encode-bit system-object-const-code))

#||
(defmacro create-system-object-term (value sort-id-code)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) system-object-const-code
	    (term$system-object __body) ,value
	    (term$sort-code __body) ,sort-id-code
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

(defmacro @create-system-object-term (value sort)
  ` (let ((__cell (allocate-chaos-term-cell))
	  (__body (allocate-chaos-term-body)))
      (setf (body-1st __body) pre-system-object-const-code
	    (term$system-object __body) ,value
	    (term$sort __body) ,sort
	    (body-4th __body) nil
	    (term-body __cell) __body)
      __cell))

||#

(defmacro make-system-object-term (__value __sort)
  `(create-term (list pre-system-object-const-code ,__value ,__sort)))

;;;*****************************************************************************
;;; BASIC UTILITIES
;;;*****************************************************************************

(defconstant all-term-code
  (logior variable-type application-form-type lisp-code-type
	  builtin-constant-type psuedo-constant-type system-object-type))

;;; TERM? : object -> bool
;;; we don't need fast predicate, this is not used as rewriting nor parsing.
;;;
(defmacro term? (!object) 
  (once-only (!object)
    ` (and (consp ,!object)
	   (consp (car ,!object))
	   (let ((type (caar ,!object)))
	     (and (integerp type)
		  (test-and all-term-code type))))))

;;; TERM-BUILTIN-EQUAL : term1 term2 -> bool
;;; assume term1 is builtin constant term
;;;
(defmacro term$builtin-equal (*_builtin-body *_term-body)
  (once-only (*_term-body)
    ` (and (term$is-builtin-constant? ,*_term-body)
	   (equal (term$builtin-value ,*_builtin-body)
		  (term$builtin-value ,*_term-body)))))

(defmacro term-builtin-equal (*_bi-term *_term)
  `(term$builtin-equal (term-body ,*_bi-term) (term-body ,*_term)))

;;; TERM-IS-CONSTANT? : term -> bool
;;; *note* we include variable-type and psuedo-constant-type for safety.
;;;
(defconstant priori-constant-type
  (logior variable-type lisp-code-type builtin-constant-type
	  psuedo-constant-type
	  system-object-type))

(defmacro term$is-constant? (*_body)
  (once-only (*_body)
    `(or (test-and priori-constant-type (term$code ,*_body))
         (null (term$subterms ,*_body)))))

(defmacro term-is-constant? (*_term)
  `(term$is-constant? (term-body ,*_term)))

;;; TERM-VARIABLES : term -> LIST[variable]
;;;
(defun term-variables (term)
  (let ((body (term-body term)))
    (cond ((term$is-variable? body) (list term))
	  ((term$is-constant? body) nil)
	  (t (let ((res nil))
	       (dolist (st (term$subterms body) res)
		 (setq res (nunion res (term-variables st) :test #'eq))))))))

(declaim (inline variables-occur-at-top?))

#+GCL
(si:define-inline-function variables-occur-at-top? (term)
  (block variables-occur-at-top-exit
    (dolist (st (term-subterms term))
      (when (term-is-variable? st)
	(return-from variables-occur-at-top-exit t)))))

#-GCL
(defun variables-occur-at-top? (term)
  (block variables-occur-at-top-exit
    (dolist (st (term-subterms term))
      (when (term-is-variable? st)
	(return-from variables-occur-at-top-exit t)))))
  
;;; TERM-IS-GROUND? : term -> bool
;;;
(defconstant apriori-ground-type	; not used now.
  (logior lisp-code-type builtin-constant-type system-object-type))

(defmacro term$is-ground? (*_body)
  (once-only (*_body)
    ` (block success
	(cond ((term$is-variable? ,*_body) (return-from success nil))
	      ((term$is-application-form? ,*_body)
	       (dolist (st (term$subterms ,*_body) t)
		 (unless (term-is-ground? st)
		   (return-from success nil))))
	      (t t)))))

(defun term-is-ground? (xx_term)
  (term$is-ground? (term-body xx_term)))

;;; SIMPLE-COPY-TERM : term -> new-term
;;; copies term.
;;;
(defun simple-copy-term (term)
  (copy-tree term))

;;; The followings are only meaningful for encoded terms ***********************
;;;*****************************************************************************

;;; TERM-VARIABLE-MATCH : variable-body term-body -> bool
;;; true iff term-body matches varible-body
;;;
(defmacro !term-variable-match (*_variable-body *_term-body)
  (once-only (*_variable-body *_term-body)
  ` (test-and (term$sort-code ,*_variable-body)
	      (term$sort-code ,*_term-body))))

(defmacro term-variable-match (*_variable_ *_term_)
  ` (!term-variable-match (term-body ,*_variable_)
			  (term-body ,*_term_)))

;;; TERM-OPERATOR-EQ : term -> bool
;;;
(defmacro !term-operator-eq (_*term-body1 _*term-body2)
  `(= (term$op-code ,_*term-body1) (term$op-code ,_*term-body2)))

(defmacro term-operator-eq (_*term1 _*term2)
  `(!term-operator-eq (term-body ,_*term1) (term-body ,_*term2)))

;;; TERM-OPERATOR-EQUAL : term -> bool
;;;
(defmacro !term-operator-equal (__*term-body1 __*term-body2)
  (once-only (__*term-body1 __*term-body2)
  ` (and (term$operator-eq ,__*term-body1 ,__*term-body2)
	 (= (term$sort-code ,__*term-body1) (term$sort-code ,__*term-body2)))))

(defmacro term-operator-equal (__*term1_ __*term2_)
  `(!term-operator-equal (term-body ,__*term1_) (term-body ,__*term2_)))

;;; EOF
