{: Copyright (C) Helmut Brandl  <helmut dot brandl at gmx dot net>

   This file is distributed under the terms of the GNU General Public License
   version 2 (GPLv2) as published by the Free Software Foundation. :}

use predicate; function end

deferred class PARTIAL_ORDER end

PO:  PARTIAL_ORDER
PO2: PARTIAL_ORDER


(<=) (a,b:PO): BOOLEAN   deferred end

(=)  (a,b:PO): BOOLEAN   deferred end

all(a,b,c:PO)
    deferred
    ensure
        a = a
        a <= a                               -- reflexive
        (a <= b) ==> (b <= a) ==> (a = b)    -- antisymmetric
        (a <= b) ==> (b <= c) ==> (a <= c)   -- transitive
    end


deferred class PARTIAL_ORDER
inherit        ANY end



(<)  (a,b:PO): BOOLEAN  -> a /= b and a <= b

(>=) (a,b:PO): BOOLEAN  -> b <= a

(>)  (a,b:PO): BOOLEAN  -> b < a

is_lower_bound (a:PO, p:PO?): ghost BOOLEAN -> all(x) p(x) ==> a <= x

is_upper_bound (a:PO, p:PO?): ghost BOOLEAN -> all(x) p(x) ==> x <= a

is_least (a:PO, p:PO?): ghost BOOLEAN    -> p(a) and a.is_lower_bound(p)

is_greatest (a:PO, p:PO?): ghost BOOLEAN -> p(a) and a.is_upper_bound(p)

is_minimal (a:PO, p:PO?): ghost BOOLEAN  -> p(a) and all(x) x < a ==> not p(x)

is_maximal (a:PO, p:PO?): ghost BOOLEAN  -> p(a) and all(x) a < x ==> not p(x)

upper_bounds (p:PO?): ghost PO? -> {x: x.is_upper_bound(p)}

lower_bounds (p:PO?): ghost PO? -> {x: x.is_lower_bound(p)}

is_infimum (a:PO, p:PO?): ghost BOOLEAN  -> a.is_greatest(p.lower_bounds)

is_supremum (a:PO, p:PO?): ghost BOOLEAN -> a.is_least(p.upper_bounds)

is_monotonic(f:PO->PO): ghost BOOLEAN ->
    all(a,b:PO) {a,b} <= f.domain ==> a <= b ==> f(a) <= f(b)

is_antitonic(f:PO->PO): ghost BOOLEAN ->
    all(a,b:PO) {a,b} <= f.domain ==> a <= b ==> f(b) <= f(a)

is_ascending(f:PO->PO): ghost BOOLEAN ->
    all(a) (f.domain)(a) ==> a <= f(a)

is_descending(f:PO->PO): ghost BOOLEAN ->
    all(a) (f.domain)(a) ==> f(a) <= a


is_closure_map(f:PO->PO): ghost BOOLEAN ->
    f.is_total and
    f.is_ascending and
    f.is_monotonic and
    f.is_idempotent



all(a,b,c:PO)
    require
        a < b
        b <= c
    proof
        require a = c
        proof   c = a
                a in {x: b <= x}
        ensure  false end
    ensure
        a /= c
    end

all(a,b,c:PO)
    require
        a <= b
        b < c
    proof
        require a = c
        proof   c in {x: x <= b}
        ensure  false end
    ensure
        a /= c
    end

all(a,b,c:PO)
    require
        a < b
        b < c
    ensure
        a < c
    end

all(a,b:PO, p:PO?) require a.is_least(p)
                           b.is_least(p)
                   ensure  a = b end

all(a,b:PO, p:PO?) require a.is_greatest(p)
                           b.is_greatest(p)
                   ensure  a = b end

all(a,b:PO, p:PO?) ensure  a.is_infimum(p)  ==> b.is_infimum(p)  ==> a = b
                           a.is_supremum(p) ==> b.is_supremum(p) ==> a = b
                   end

all(a,b:PO, p:PO?)
    require
       a <= b
       b.is_lower_bound(p)
    ensure
       a.is_lower_bound(p)
    end


all(a:PO)
    proof
        all(x) require  {a}(x)
               proof    x = a
                        {y: y <= x}(a)
               ensure   a <= x end
    ensure
        a.is_lower_bound({a})
    end


all(x:PO, p,q:PO?)
    require
        x.is_lower_bound(p)
        x.is_lower_bound(q)
    proof
        all(y) require (p + q)(y)
               proof   p(y) ==> x <= y
               ensure  x <= y end
    ensure
        ((p + q).lower_bounds)(x)
    end



all(x:PO, p,q:PO?)
    require
        ((p + q).lower_bounds)(x)
    ensure
        x.is_lower_bound(p)
        x.is_lower_bound(q)
    end

all(a,b:PO, p,q:PO?)
    require
        a.is_infimum(p)
        b.is_infimum(q)
        p <= q
    proof
        b.is_lower_bound(p)
    ensure
        b <= a
    end

all(a:PO, p:PO?)
    require
        a.is_least(p)
    proof
        all(x) require x.is_lower_bound(p)
               proof   all(y) p(y) ==> x <= y
                       p(a)
               ensure  x <= a end
    ensure
        a.is_infimum(p)
    end

all(a:PO)
    proof
        a.is_least({x: a <= x})
    ensure
        a.is_infimum({x: a <= x})
    end


{:
all(a:PO, f:PO->PO)
    require
        f.is_closure_map
    proof
        f(a).is_fixpoint(f)

        all(x)
            require
                x.is_fixpoint(f)
                a <= x
            proof
                f(a) <= f(x)
                f(x) = x
            ensure
                f(a) <= x
            end
    ensure
        f(a).is_least({x: x.is_fixpoint(f) and a <= x})
    end
:}

G: ANY

immutable class predicate.PREDICATE[G]
inherit   ghost PARTIAL_ORDER
end