#!/usr/bin/env perl
package main;
use warnings;
use strict;
use Data::Dumper;
use Carp;
use Getopt::Long qw(:config gnu_getopt);
use Pod::Usage;
use File::Basename;
use PPI;
use List::Util 'max';
use Algorithm::Permute qw(permute);

my $INH  = *ARGV;
my $ERRH = *STDERR;
my $OUTH = *STDOUT;
GetOptions(
    \%ARGV,
    'input|i=s',
    'output|o=s',
    'debug:i',
    'quiet'   => sub { $ARGV{quiet}   = 1; no diagnostics;  no warnings },
    'verbose' => sub { $ARGV{verbose} = 1; use diagnostics; use warnings },
    'version' => sub {
        pod2usage
          -sections => [ 'VERSION', 'REVISION' ],
          -verbose  => 99;
    },
    'license' => sub {
        pod2usage
          -sections => [ 'AUTHOR', 'COPYRIGHT' ],
          -verbose  => 99;
    },
    'usage' => sub {
        pod2usage
          -sections => ['SYNOPSIS'],
          -verbose  => 99;
    },
    'help'   => sub { pod2usage -verbose => 1 },
    'manual' => sub { pod2usage -verbose => 2 },
) or pod2usage( -verbose => 1 );

IO:
{

    # We use the ARGV magical handle to read input
    # If user explicitly sets -i, put the argument in @ARGV
    if ( exists $ARGV{input} ) {
        unshift @ARGV, $ARGV{input};
    }

    # Allow in-situ arguments (equal input and output filenames)
    # FIXME: infinite loop. Why?
    if (    exists $ARGV{input}
        and exists $ARGV{output}
        and $ARGV{input} eq $ARGV{output} )
    {
        croak "Bug: don't use in-situ editing (same input and output files";
        open $INH, q{<}, $ARGV{input}
          or croak "Can't read $ARGV{input}: $!";
        unlink $ARGV{input};
    }

    # Redirect STDOUT to a file if so specified
    if ( exists $ARGV{output} and q{-} ne $ARGV{output} ) {
        open $OUTH, q{>}, $ARGV{output}
          or croak "Can't write $ARGV{output}: $!";
    }
}

my %files;
foreach my $file (@ARGV) {

    # Load a document from a file
    my $document = PPI::Document->new($file);

    # Strip out comments
    $document->prune('PPI::Token::Comment');

    # $document->normalized;
    # $document->index_locations;

    # Find all the named subroutines
    my $sub_nodes =
      $document->find( sub { $_[1]->isa('PPI::Statement::Sub') and $_[1]->name }
      );

    next unless $sub_nodes;
    my %sub_names = map {
        $_->name => {
            'code' =>

              #$_->content
              'code'
          }
    } @$sub_nodes;

    my $file_name = fileparse $file;
    $files{$file_name} = \%sub_names;
}

#     foreach my $sub_name (keys %sub_names) {
# 	eval $sub_names{$sub_name};
# 	use B::Deparse;
# 	my $deparse = B::Deparse->new("-p", "-sC");
# 	my $body = $deparse->coderef2text(\&$sub_name);          #This only works like half the time. No idea why.

#Set up @file_names and @sub_names for easy reference
my @file_names = sort keys %files;
my @sub_names;
foreach my $sub_hash ( values %files ) {
    foreach my $sub_name ( keys %{$sub_hash} ) {
        push @sub_names, $sub_name;
    }
}

#remove duplicates and sort
my %hash = map { $_, 1 } @sub_names;
@sub_names = sort keys %hash;

#Put a second key into each subroutine hash, pointing to an array of the files the subroutine is used in.
#Each element in the array is a hash.
foreach my $sub_name (@sub_names) {
    my @file_names_by_sub;
    foreach my $file_name (@file_names) {
        if ( $files{$file_name}->{$sub_name} ) {
            push @file_names_by_sub, $file_name;
        }
    }
    foreach my $file_name_by_sub (@file_names_by_sub) {
        foreach my $file_name (@file_names) {
            %{ $files{$file_name}->{$sub_name}->{'other files'}
                  ->{$file_name_by_sub} } = %{ $files{$file_name} }
              unless !$files{$file_name}->{$sub_name}
                  or $file_name eq $file_name_by_sub
            ;    #keeps it from pointing to itself, and from creating new keys.
        }
    }
}

{
    local $Data::Dumper::Maxdepth = 4;
  #  print Dumper \%files;
 #   exit;
}

#print Dumper keys %{ $files{'test.pl'}{'get_file'}{'files'}{'test.pl'} };
#exit;

##print out a table showing which files contain which subroutines.
#print norm(" ", @file_names);
print join( "\t", q{}, @sub_names ), "\n";

foreach my $file_name (@file_names) {
    print $file_name, "\t";
    foreach my $sub_name (@sub_names) {
        if ( $files{$file_name}->{$sub_name} ) {
            print q{*};
        }
        else { print q{}; }
        print "\t";
    }
    print "\n";
}

#hamming distance part -- I'll do this without permutations first.
#Algorithm::Permute::permute { push @things, join "", @thing; } @thing;
my %hd_by_sub_name;

foreach my $sub_name (@sub_names) {
    my %code_of_sub_variations;
    foreach my $file ( keys %files ) {
        foreach my $my_sub_name ( keys %{ $files{$file} } ) {
            if ( $sub_name eq $my_sub_name ) {
                $code_of_sub_variations{$file} =
                  $files{$file}->{$my_sub_name}->{'code'};
            }
        }
    }
    $hd_by_sub_name{$sub_name} = hd_all_combinations(%code_of_sub_variations);
}
print Dumper %hd_by_sub_name;
exit;

#table of files and subs that appear in them.         check
#possibly number of times each is called.
#then do Hamming distance for subs with the same name, using the permutations thing to match subs that have the same words in different order.





# Takes a hash representing a single subroutine. keys are files, values are the code of the subroutine in that file.
# Returns a hash with keys being a filename pointing to a hash whose keys are another filename and whose value is the hd for the sub between those two files.
# So to find the hd between file2 and file3, do $hash{file2}{file3} or $hash{file3}{file2}.
sub hd_all_combinations {
    my (%hash) = @_;
    my @files = keys %hash;
    my %ret_hash;
    my @combinations;

    while (my $file1 = shift @files) {
	foreach my $file2 (@files) {
	    my @combo = ($file1, $file2);
	    push @combinations, \@combo;
	}
    }

    for my $combo (@combinations) {
	my $file1 = @{$combo}[0];
	my $file2 = @{$combo}[1];
	$ret_hash{$file1}->{$file2} = hd($hash{$file1}, $hash{$file2});
	$ret_hash{$file2}->{$file1} = hd($hash{$file1}, $hash{$file2});

    }
    return \%ret_hash;
}
    


sub hd {
  my ($k, $l) = @_;
  my $diff = $k ^ $l;
  my $num_mismatch = $diff =~ tr/\0//c;
}



sub norm {
    my ( $string, @strings ) = @_;
    my $longest = max( map { length } @strings );
    until ( length $string == $longest ) {
        $string = "$string ";
    }
    return $string;
}




__DATA__

__END__
=head1 NAME

 APerlyName.pl - Short description

=head1 SYNOPSIS

 APerlyName.pl [OPTION]... [FILE]...

=head1 DESCRIPTION

 Long description

=head1 OPTIONS

 -i, --input       filename to read from                            (STDIN)
 -o, --output      filename to write to                             (STDOUT)
     --debug       print additional information
     --verbose     print diagnostic and warning messages
     --quiet       print no diagnostic or warning messages
     --version     print current version
     --license     print author's contact and copyright information
     --help        print this information
     --manual      print the plain old documentation page

=head1 VERSION

 0.0.1

=head1 REVISION

 $Rev: $:
 $Author: $:
 $Date: $:
 $HeadURL: $:
 $Id: $:

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
