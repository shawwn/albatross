use
    predicate
end

G:ANY

class
    OPTION[G]
create
    none
    value(item:G)
end

item (o:OPTION[G]): G
    require
        o as value(v)
    ensure
        -> inspect o
           case value(v) then v
    end
