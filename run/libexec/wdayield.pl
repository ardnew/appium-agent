#!/usr/bin/env -S perl

# This script simulates "follow" mode of the `tail -f` utility, but it adds 
# support for a read timeout to ensure the script will always eventually exit.
# This makes it suitable for use as a LaunchAgent with launchctl(1).
#
# The script exits with success if data matching the given regular expression
# is found in the input. Otherwise, the script exits with an error status due
# to timeout.
#
# So, this script is more accurately described as `tail -f | grep -m 1` with a 
# timeout condition on `tail`.
#
# Reading _any_ data from the input resets the timeout timer. The script will
# only timeout when nothing has written to the input for the timeout duration.
#
# The "follow" mode continuously reads a file, but it does not stop at EOF.
# Instead, it waits for and then reads all new data appended. Typically, this
# process continues indefinitely until killed manually by the user via SIGINT.
use strict;
use warnings;

use File::Basename;

# Disable output buffering
$| = 1;

my $self = basename($0);

die << "_usage_" unless @ARGV > 0 and -f $ARGV[0];
usage:
  ${self} wda-log-path [search-pattern]
_usage_

open my $fh, "<", $ARGV[0] or die $!;

my $search = $ARGV[1] || qr'ServerURLHere->(http://[\d\.]+:\d+)<-ServerURLHere';

# the SIGALRM signal is fired when a certain number of seconds have elapsed 
# since the last successful read from the given log file.
$SIG{ALRM} = sub { die "timeout: WDA server (stdin)\n" };

# Using 5 minute timeout, because Xcode can be insanely slow. Anything less and
# we will often kill the process while building a large source file.
my %idle = (
  max => 60.0 * 5, # kill ourself if no input read after $idle{max} seconds
  per => 0.25, # time to wait for more input after each EOF encountered
  sum => 0.00, # sleep for per seconds and repeat while sum+=per <= max

  # with max=20.0 and per=0.25, then timeout occurs after
  # reading 80 (20.0/0.25) consecutive 0-byte reads at EOF.
);

my %seek = (
  prev => -1,
  curr => -1,
);

for (;;) {
  # install read timeout alarm before first read
  alarm $idle{max}; 

  # read entire file until we encounter the banner containing our server URL.
  for ($seek{curr} = tell($fh); <$fh>; $seek{curr} = tell($fh)) {
    # clear alarm on every successful read, regardless if it contains the URL.
    alarm 0; 
    # if the URL is found, print it and exit with successful status
    if (m{$search}) {
      print($1), exit(0);
    }
    # reinstall read timeout alarm
    alarm $idle{max}; 
  }

  # side-effect of this form of select() will delay by the given fractional
  # number of seconds.
  select(undef, undef, undef, $idle{per});

  # seek to where we had been
  seek($fh, $seek{curr}, 0);  

  # check if our seek index has changed
  if ($seek{prev} == $seek{curr}) { 

    # no change, increment towards timeout
    $idle{sum} += $idle{per}; 
    if ($idle{sum} >= $idle{max}) {
      die "timeout: WDA server (eof)\n";
    } else {
      # print time remaining until timeout every second
      if ($idle{sum} - int($idle{sum}) < $idle{per}) {
        printf STDERR "idle: timeout in %d seconds\n", 
          $idle{max} - int($idle{sum});
      }
    }

  } else {
    # reset timeout on file seek
    ($seek{prev}, $idle{sum}) = ($seek{curr}, 0); 
  }
}
