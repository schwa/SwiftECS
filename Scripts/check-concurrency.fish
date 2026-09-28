#!/usr/bin/env fish

set root (path resolve (path dirname (status filename))/..)
set fixtures $root/Scripts/ConcurrencyCompileChecks
mkdir -p $root/.build
set scratch (mktemp -d $root/.build/concurrency-check.XXXXXX)
function cleanup --on-event fish_exit --inherit-variable scratch
    rm -rf $scratch
end
mkdir -p $scratch/Sources/ConcurrencyCheck
cp $fixtures/Package.swift.fixture $scratch/Package.swift

for fixture in $fixtures/*.valid.swift.fixture $fixtures/*.invalid.swift.fixture
    cp $fixture $scratch/Sources/ConcurrencyCheck/main.swift
    xcb build --path $scratch --raw >$scratch/build.log 2>&1
    set result $status
    if string match -q '*.valid.swift.fixture' $fixture
        if test $result -ne 0
            cat $scratch/build.log
            exit 1
        end
    else
        if test $result -eq 0
            printf 'Unexpected compilation success: %s\n' $fixture
            exit 1
        end
        if not rg --quiet --fixed-strings --file $fixture.error $scratch/build.log
            cat $scratch/build.log
            printf 'Wrong rejection diagnostic: %s\n' $fixture
            exit 1
        end
    end
    printf 'PASS %s\n' (path basename $fixture)
end
