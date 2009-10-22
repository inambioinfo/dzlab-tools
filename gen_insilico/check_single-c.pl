#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;
use Carp;
use Getopt::Long;
use Pod::Usage;
use List::Util qw /sum/;

my $output;

# Grabs and parses command line options
my $result = GetOptions (
    'output|o=s'  => \$output,
    'verbose|v'   => sub { use diagnostics; },
    'quiet|q'     => sub { no warnings; },
    'help|h'      => sub { pod2usage ( -verbose => 1 ); },
    'manual|m'    => sub { pod2usage ( -verbose => 2 ); }
);

# Check required command line parameters
pod2usage ( -verbose => 1 )
unless @ARGV and $result;

if ($output) {
    open my $USER_OUT, '>', $output or croak "Can't open $output for writing: $!";
    select $USER_OUT;
}

my $total_lines = 0;
my $total_comms = 0;
my $total_attrs = 0;
my %chromosomes = ();

my $input_file  = $ARGV[0];

while (<>) {
    if (m/^\s*#/) {
        $total_comms++;
        next;
    }
    chomp;

    my @fields = split /\t/, $_;
    my $attribute = $fields[-1];
    $chromosomes{$fields[0]}{$fields[3]}++;

    $total_attrs++ unless $attribute =~ m/c=\d+;t=\d+/;
    $total_lines++;

}

for my $chr (sort keys %chromosomes) {
    my $dups = 0;
    for my $start (keys %{$chromosomes{$chr}}) {
        $dups++ if $chromosomes{$chr}{$start} > 1;
    }
    $chromosomes{$chr} = $dups;
}

my $line_length = length $input_file;

print q{=} x $line_length, "\n";
print "$input_file\n";
print q{-} x $line_length, "\n";
print "Lines:\t\t$total_lines\n";
print "Comments:\t$total_comms\n";
print "Bad attrs:\t$total_attrs\n";
print "Duplicates:\t", sum (values %chromosomes), "\t(", join (q{,}, map { "$_:$chromosomes{$_}" } sort keys %chromosomes), ")\n";
print q{=} x $line_length, "\n";

print STDERR "$input_file looks ", $total_attrs ? 'BAD' : 'OK', "\n";

__END__


=head1 NAME

 name.pl - Short description

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

 name.pl [OPTION]... [FILE]...

 -o, --output      filename to write results to (defaults to STDOUT)
 -v, --verbose     output perl's diagnostic and warning messages
 -q, --quiet       supress perl's diagnostic and warning messages
 -h, --help        print this information
 -m, --manual      print the plain old documentation page

=head1 REVISION

 Version 0.0.1

 $Rev: $:
 $Author: $:
 $Date: $:
 $HeadURL: $:
 $Id: $:

=head1 AUTHOR

 Pedro Silva <psilva@nature.berkeley.edu/>
 Zilberman Lab <http://dzlab.pmb.berkeley.edu/>
 Plant and Microbial Biology Department
 College of Natural Resources
 University of California, Berkeley

=head1 COPYRIGHT

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see <http://www.gnu.org/licenses/>.

=cut