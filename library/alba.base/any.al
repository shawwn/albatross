use boolean end

deferred class ANY end

G: ANY


(=)  (a,b:G): BOOLEAN    deferred end

(/=) (a,b:G): BOOLEAN -> not (a = b)

all(a:G) deferred ensure a = a end


all(a:G)
    require
        a /= a
    ensure
        false
    end


immutable class boolean.BOOLEAN
inherit         ANY end