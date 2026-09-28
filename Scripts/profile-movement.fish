#!/usr/bin/env fish

set mode 1
set frames 240
set duration 8
if set -q argv[1]
    set mode $argv[1]
end
if set -q argv[2]
    set frames $argv[2]
end
if set -q argv[3]
    set duration $argv[3]
end
set directory (mktemp -d /tmp/swiftecs-profile.XXXXXX)
printf 'Profile artifacts: %s\n' $directory
env ECS_RUN_MOVEMENT_BENCHMARKS=1 ECS_MOVEMENT_MODE=$mode ECS_MOVEMENT_ROUNDS=1 ECS_MOVEMENT_FRAMES=$frames ECS_MOVEMENT_PROFILE_READY=$directory/ready xcb test SwiftECS/SwiftECS -c release --raw -- --filter MovementParallelBenchmarkTests >$directory/run.log 2>&1 &
set runner $last_pid
while kill -0 $runner 2>/dev/null
    if test -s $directory/ready
        break
    end
end
if not test -s $directory/ready
    wait $runner
    /bin/cat $directory/run.log
    exit 1
end
set target (string trim (/bin/cat $directory/ready))
sample $target $duration 1 -mayDie -file $directory/stacks.sample >$directory/sample.log 2>&1
set samplingStatus $status
wait $runner
set runStatus $status
/bin/cat $directory/sample.log
rg 'SUMMARY|Test run with|error:' $directory/run.log
if test $samplingStatus -ne 0; or test $runStatus -ne 0
    exit 1
end
