#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;
use Carp;
use Getopt::Long;
use Pod::Usage;

my $DATA_HANDLE = 'ARGV';
my $output;
my $size    = 10;
my $column  = 6;
my $numeric = 1;

# Grabs and parses command line options
my $result = GetOptions (
    'size|s=i'        => \$size,
    'sort-column|c=i' => \$column,
    'numeric|n'       => \$numeric,
    'output|o=s'  => \$output,
    'verbose|v'   => sub { use diagnostics; },
    'quiet|q'     => sub { no warnings; },
    'help|h'      => sub { pod2usage ( -verbose => 1 ); },
    'manual|m'    => sub { pod2usage ( -verbose => 2 ); }
);

# Check required command line parameters
pod2usage ( -verbose => 1 )
unless @ARGV and $result;

my @data  = <>;
my $lines = sort_and_count (\@data, --$column, $numeric);

croak "size parameter is greater than number of lines in file: $size > $lines\n"
if $size > $lines;

my $index = 1;
mkdir "$output.$size";
for (my $i = 0; $i < @data - $size; $i += int ($lines / $size)) {
    open my $PARTITION, '>', "$output.$size/$output." . $index++ or croak "Can't write file: $!";
    print $PARTITION join (q{}, @data[$i .. $i + ($lines / $size)]);
    close $PARTITION;
}

sub sort_and_count {
    my ($data_in, $column, $numeric) = @_;

    if ($numeric) {
        no warnings;
        @$data_in = sort { (split /\t/, $a)[$column] <=> (split /\t/, $b)[$column] } @$data_in;
    }
    else {
        @$data_in = sort { (split /\t/, $a)[$column] cmp (split /\t/, $b)[$column] } @$data_in;
    }
}


__END__


=head1 NAME

 partitioner.pl - Split a column-based file into sorted partitions

=head1 SYNOPSIS

 # sort and split a gff file on its score column (#6) into deciles with output filenames prefixed by base_name
 partitioner.pl in.gff -s 10 -c 6 -o base_name

 # sort and split a gff file on its score column (#6) into percentiles with output filenames prefixed by base_name
 partitioner.pl in.gff -s 100 -c 6 -o base_name

=head1 DESCRIPTION

=head1 OPTIONS

 name.pl [OPTION]... [FILE]...

 -s, --size        percentage of total lines in file per partition (10)
 -c, --sort-column column index (base 1) on which to sort and split (6)
 -n, --numeric     do numeric sort instead of alphanumeric (default)  
 -o, --output      basename to write results to (basename.0, basename.1 etc)
 -v, --verbose     output perl's diagnostic and warning messages
 -q, --quiet       supress perl's diagnostic and warning messages
 -h, --help        print this information
 -m, --manual      print the plain old documentation page

=head1 REVISION

 Version 0.0.1

 $Rev$:
 $Author$:
 $Date$:
 $HeadURL$:
 $Id$:

=head1 AUTHOR

 Pedro Silva <pedros@berkeley.edu/>
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
