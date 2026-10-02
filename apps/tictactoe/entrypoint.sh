#!/bin/sh
# The container's first process: lighttpd in the background, and a line on stdout every
# five seconds (cthulhu wants to hear from a container; it is also what the lab's test
# looks for). A stop from the framework ends both.
trap 'echo "tictactoe: stopping"; kill -TERM "$pid" 2>/dev/null; wait "$pid"; exit 0' TERM INT

/usr/sbin/lighttpd -D -f /srv/tictactoe/lighttpd.conf &
pid=$!
echo "tictactoe: lighttpd pid=$pid, the page is on port 8090"

i=0
while kill -0 "$pid" 2>/dev/null; do
    i=$((i + 1))
    echo "tictactoe alive #$i host=$(hostname)"
    sleep 5
done
echo "tictactoe: lighttpd exited"
exit 1
