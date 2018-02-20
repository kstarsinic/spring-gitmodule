#!/usr/bin/env perl

use strict;
use warnings;

use lib "$ENV{HOME}/Dropbox/lib";

use JSON;
use Data::Dumper;
$Data::Dumper::Indent = 0;
$Data::Dumper::Terse  = 1;

use List::Util        qw(max);

use Getopt::LucidPlus qw(:all);
my $GOLP  = Getopt::LucidPlus->new(
  [
    Counter('--debug'),
    List('--show'),
  ],
  { strict => 1 },
);
die $GOLP->usage, $GOLP->dump('getopt') if not eval { $GOLP->getopt };
die $GOLP->usage, $GOLP->dump('validate') if not eval { $GOLP->validate };
my %Opt = $GOLP->options;

my %M = (
  owner               => { skip => -1, },
  permissions         => { skip => -1, },

  full_name           => { skip => -1 },
  name                => { skip => -1 },
  id                  => { skip => -1 },

  has_downloads       => { skip => -1 },
  has_issues          => { skip => -1 },
  has_projects        => { skip => -1 },
  has_wiki            => { skip => -1 },

  size                => { maxw => 12 },
  forks_count         => { maxw => 12 },
  open_issues_count   => { maxw => 12 },
  stargazers_count    => { maxw => 12, alias => '*gazers', },
  watchers_count      => { maxw => 12 },

  _summary            => [
    [ qw(description) ],
    [ qw(homepage) ],
    [ qw(clone_url) ],
    [ qw(language) ],
    [ qw(created_at pushed_at updated_at) ],
    [ qw(size forks_count open_issues_count watchers_count stargazers_count) ],
  ],
);

my @F;        # [ [ $hformat, $rformat, @fieldnames ] ]
foreach my $i (0 .. $#{ $M{_summary} }) {
  my @fields  = @{ $M{_summary}[$i] };
  my $n       = $i + 1;

  if (@fields == 1) {
    $M{$fields[0]}{skip}  = -10 * $n;
    $M{$fields[0]}{maxw}  = -1;
    push @F, [ undef, "  %-20s %s\n", $fields[0] ];
  } else {
    foreach my $j (0 .. $#fields) {
      $M{$fields[$j]}{skip}   = $n;
      $M{$fields[$j]}{order}  = $j;
    }

    push @F, [
      '  ' . join('  ', map { get_metadata($_, 'hformat') } @fields) . "\n",
      '  ' . join('  ', map { get_metadata($_, 'rformat') } @fields) . "\n",
      @fields,
    ],
  }
}

# watchers is an alias for watchers_count, etc.
$M{$_}{skip} //= -99 for map { /(.+)_count$/ } keys %M;

my %D;

foreach my $file (@ARGV) {
  print "file $file:\n";
  open my $fh, '<', $file or die "Could not open $file for reading: $!";
  my $d = decode_json(join '', <$fh>);
  close $fh;

  fix_meta(@$d);

  foreach my $item (sort { json_val($a, 'clone_url') cmp json_val($b, 'clone_url') } @$d) {
    foreach my $f (@F) {
      my ($hformat, $rformat, @fields) = @$f;

      if ($hformat) {
        printf $hformat, map { get_metadata($_, 'alias') } @fields;
        printf $rformat, map { json_val($item, $_) // "<$_>" } @fields;
      } else {
        my @vals = map { json_val($item, $_) } @fields;

        if (grep { defined } @vals) {
          printf $rformat, @fields, @vals;
        }
      }
    }

    foreach my $key (sort keys %$item) {
      my $val = json_val($item, $key);

      if (defined $val and length($val) > get_metadata($key, 'maxw') and not get_metadata($key, 'skip')) {
        die sprintf "key [%s] has length %d: %s %s", $key, length($val), Dumper($val), Dumper($M{$key});
      }
    }

    my %vk;
    foreach my $key (sort keys %$item) {
      my $val = json_val($item, $key);

      ++$D{$key};

      if (defined $val) {
        push @{ $vk{$val} }, $key;
        printf "  %-18s %s\n", $key, $val unless $M{$key} && $M{$key}{skip};
        die sprintf("%s: bad metadata %s", $key, Dumper($M{$key})) if grep { not defined } $M{$key}, $M{$key}{maxw};
      }
    }

    if ($Opt{debug}) {
      if (my @dupes = (grep { not /^\d+$/ and @{ $vk{$_} } > 1 } keys %vk)) {
        print "---\n";
        printf "  %-70s %s\n", $_, "@{ $vk{$_} }" for sort @dupes;
      }
    }

    print "\n";
  }
}


# print "Statistics:\n";
# foreach my $key (sort keys %D) { printf "  %-28s %4d\n", $key, $D{$key}; }

sub json_val {
  my ($kv, $key)  = @_;
  my $in          = $$kv{$key};

  if (defined $in) {
    if (JSON::is_bool($in)) {
      return $in ? 'true' : undef;
    }

    return $in if ref $in;

    return if ($key eq 'default_branch' and $in eq 'master');
    return if ($key eq 'language' and $in eq 'Java');
    return if $key eq '';
    return $in;
  }

  return undef;
}


sub get_metadata {
  my ($field, $key) = @_;

  # printf "get_metadata(%s, %s)\n", Dumper($field), Dumper(\$key);

  if (not defined $M{$field}{skip}) {
    if ($field =~ /_url$/ or $field eq 'url') {
      $M{$field}{skip}  = -1;
    } else {
      $M{$field}{skip} = 0;
    }
  }

  if (not defined $M{$field}{alias}) {
    if ($field =~ /^(.+)_count$/) {
      $M{$field}{alias} = $1;
    } else {
      $M{$field}{alias} = $field;
    }
  }

  if (not defined $M{$field}{maxw}) {
    if ($field =~ /_url$/ or $field eq 'url') {
      $M{$field}{maxw}  = 119;
    } elsif ($field =~ /_at$/) {
      $M{$field}{maxw}  = 20;
    } else {
      $M{$field}{maxw}  = max(1, length $M{$field}{alias});
    }
  }

  if ($M{$field}{maxw} > 0) {
    $M{$field}{hformat} //= '%-' . $M{$field}{maxw} . 's';
    $M{$field}{rformat} //= '%'  . $M{$field}{maxw} . 's';

    for (my ($lhs, $char) = (1, ' '); length $M{$field}{alias} < $M{$field}{maxw}; $lhs = not $lhs) {
      if ($lhs) {
        $M{$field}{alias} = $char . $M{$field}{alias};
      } else {
        $M{$field}{alias} = $M{$field}{alias} . $char;
        $char = '.';
      }
    }

    #$M{$field}{alias} .= '.' while length $M{$field}{alias} < $M{$field}{maxw};
  } else {
    # We assume that we know what we're doing
  }

  $M{$field}{order}    //= 0;

  if (not defined $M{$field}{$key}) {
    die sprintf "get_metadata(%s, %s) = %s missing", $field, $key, Dumper(\%M);
  }

  return $M{$field}{$key};
}


sub fix_meta {
  my (@d) = @_;
  my @bad;

  foreach my $item (@d) {
    foreach my $key (sort keys %$item) {
      my $val = json_val($item, $key);

      if (defined $val and not ref $val) {
        my $skip = get_metadata($key, 'skip');
        my $maxw = get_metadata($key, 'maxw');

        if ($maxw >= 0 and length $val > $maxw and not $skip) {
          push @bad, sprintf "%-20s skip %3d maxw %3d -> %3d (%s)\n", $key, $skip, $maxw, length($val), $val;
          $M{$key}{maxw} = length($val);
        }
      }
    }
  }

  warn "bad metadata in file:\n", @bad if @bad;
}

