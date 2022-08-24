;; NOTE: Assertions have been generated by update_lit_checks.py and should not be edited.
;; RUN: wasm-opt %s --vacuum --traps-never-happen -all -S -o - | filecheck %s

(module
  (memory 1 1)

  ;; CHECK:      (type $struct (struct (field (mut i32))))
  (type $struct (struct (field (mut i32))))

  ;; CHECK:      (func $drop (param $x i32) (param $y anyref)
  ;; CHECK-NEXT:  (nop)
  ;; CHECK-NEXT: )
  (func $drop (param $x i32) (param $y anyref)
    ;; A load might trap, normally, but if traps never happen then we can
    ;; remove it.
    (drop
      (i32.load (local.get $x))
    )

    ;; A trap on a null value can also be ignored.
    (drop
      (ref.as_non_null
        (local.get $y)
      )
    )

    ;; Other ref.as* as well.
    (drop
      (ref.as_func
        (local.get $y)
      )
    )
    (drop
      (ref.as_data
        (local.get $y)
      )
    )
    (drop
      (ref.as_i31
        (local.get $y)
      )
    )

    ;; Ignore unreachable code.
    (drop
      (unreachable)
    )
  )

  ;; Other side effects prevent us making any changes.
  ;; CHECK:      (func $other-side-effects (param $x i32) (result i32)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (call $other-side-effects
  ;; CHECK-NEXT:    (i32.const 1)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (local.set $x
  ;; CHECK-NEXT:   (i32.const 2)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (i32.const 1)
  ;; CHECK-NEXT: )
  (func $other-side-effects (param $x i32) (result i32)
    ;; A call has all manner of other side effects.
    (drop
      (call $other-side-effects (i32.const 1))
    )

    ;; Add to the load an additional specific side effect, of writing to a
    ;; local. We can remove the load, but not the write to a local.
    (drop
      (block (result i32)
        (local.set $x (i32.const 2))
        (i32.load (local.get $x))
      )
    )

    (i32.const 1)
  )

  ;; A helper function for the above, that returns nothing.
  ;; CHECK:      (func $return-nothing
  ;; CHECK-NEXT:  (nop)
  ;; CHECK-NEXT: )
  (func $return-nothing)

  ;; CHECK:      (func $partial (param $x (ref $struct))
  ;; CHECK-NEXT:  (local $y (ref null $struct))
  ;; CHECK-NEXT:  (local.set $y
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (local.set $y
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $partial (param $x (ref $struct))
    (local $y (ref null $struct))
    ;; The struct.get's side effect can be ignored due to tnh, and the value is
    ;; dropped anyhow, so we can remove it. We cannot remove the local.tee
    ;; inside it, however, so we must only vacuum out the struct.get and
    ;; nothing more. (In addition, a drop of a tee will become a set.)
    (drop
      (struct.get $struct 0
        (local.tee $y
          (local.get $x)
        )
      )
    )
    ;; Similar, but with an eqz on the outside, which can also be removed.
    (drop
      (i32.eqz
        (struct.get $struct 0
          (local.tee $y
            (local.get $x)
          )
        )
      )
    )
  )

  ;; CHECK:      (func $toplevel
  ;; CHECK-NEXT:  (nop)
  ;; CHECK-NEXT: )
  (func $toplevel
    ;; A removable side effect at the top level of a function. We can turn this
    ;; into a nop.
    (unreachable)
  )

  ;; CHECK:      (func $if-unreachable-arm (param $x i32)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (if
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (nop)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (if
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (call $toplevel)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (if
  ;; CHECK-NEXT:   (i32.eqz
  ;; CHECK-NEXT:    (local.get $x)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:   (call $toplevel)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (if
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (return)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $if-unreachable-arm (param $x i32)
    ;; In all these cases we can assume the unreachable arm is never reached,
    ;; so we can turn it into a nop, and then further optimize that nop as
    ;; relevant. Some of these may require further passes to fully optimize, but
    ;; at least all the unreachables must be optimized out.
    (if
      (local.get $x)
      (unreachable)
    )
    (if
      (local.get $x)
      (nop)
      (unreachable)
    )
    (if
      (local.get $x)
      (call $toplevel) ;; something with a side effect
      (unreachable)
    )
    (if
      (local.get $x)
      (unreachable)
      (call $toplevel) ;; something with a side effect
    )
    ;; We have nothing to optimize here: the type is unreachable, but we need
    ;; an actual unreachable to optimize (a return has side effects we cannot
    ;; remove).
    (if
      (local.get $x)
      (return)
    )
  )

  ;; CHECK:      (func $if-unreachable-arms (param $x i32)
  ;; CHECK-NEXT:  (call $toplevel)
  ;; CHECK-NEXT:  (block
  ;; CHECK-NEXT:   (if
  ;; CHECK-NEXT:    (local.get $x)
  ;; CHECK-NEXT:    (nop)
  ;; CHECK-NEXT:    (nop)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:   (unreachable)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $if-unreachable-arms (param $x i32)
    ;; Both arms are unreachable. We can optimize both into nops. To avoid
    ;; changing the type, we emit an unreachable after the if, and leave fully
    ;; optimizing the if away for later passes. The call is added here just to
    ;; avoid the function body being completely optimized away by other
    ;; optimizations.
    (call $toplevel)
    (if
      (local.get $x)
      (unreachable)
      (unreachable)
    )
  )

  ;; CHECK:      (func $if-unreachable-arms-value-left (param $x i32) (result i32)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (i32.const 1)
  ;; CHECK-NEXT: )
  (func $if-unreachable-arms-value-left (param $x i32) (result i32)
    (if (result i32)
      (local.get $x)
      (unreachable)
      (i32.const 1)
    )
  )

  ;; CHECK:      (func $if-unreachable-arms-value-right (param $x i32) (result i32)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (i32.const 1)
  ;; CHECK-NEXT: )
  (func $if-unreachable-arms-value-right (param $x i32) (result i32)
    (if (result i32)
      (local.get $x)
      (i32.const 1)
      (unreachable)
    )
  )

  ;; CHECK:      (func $if-unreachable-arms-value-both (param $x i32) (result i32)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (unreachable)
  ;; CHECK-NEXT: )
  (func $if-unreachable-arms-value-both (param $x i32) (result i32)
    (if (result i32)
      (local.get $x)
      (unreachable)
      (unreachable)
    )
  )

  ;; CHECK:      (func $if-unreachable-arms-non-noppable (param $x i32) (result i32)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (return
  ;; CHECK-NEXT:   (i32.const 1)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $if-unreachable-arms-non-noppable (param $x i32) (result i32)
    (if (result i32)
      (local.get $x)
      ;; This arm has type unreachable, but is not an unreachable. We can only
      ;; modify the other arm (which can be a nop, which then unlocks more
      ;; simplifications).
      (return
        (i32.const 1)
      )
      (unreachable)
    )
  )

  ;; CHECK:      (func $if-unreachable-arms-no-value (param $x i32) (result i32)
  ;; CHECK-NEXT:  (if
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (return
  ;; CHECK-NEXT:    (i32.const 1)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:   (nop)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (unreachable)
  ;; CHECK-NEXT: )
  (func $if-unreachable-arms-no-value (param $x i32) (result i32)
    ;; As above, but the if has no return value. We can nop one arm, but must be
    ;; careful to leave an unreachable on the outside so the type does not
    ;; change. The if is not fully optimized here, but later passes can do so.
    (if
      (local.get $x)
      (return
        (i32.const 1)
      )
      (unreachable)
    )
  )
)
