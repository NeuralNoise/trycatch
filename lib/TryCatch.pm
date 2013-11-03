package TryCatch;

use strict;
use warnings;

use base 'TryCatch::Lite';

use Parse::Method::Signatures;
use Moose::Util::TypeConstraints;

our $VERSION = '1.003001';

use namespace::clean;

use Sub::Exporter -setup => {
  exports => [qw/try/],
  groups => { default => [qw/try/] },
  installer => sub {
    my ($args, $to_export) = @_;
    my $pack = $args->{into};
    my $ctx_class = $args->{parser} || 'TryCatch';

    foreach my $name (@$to_export) {
      if (my $parser = __PACKAGE__->can("_parse_${name}")) {
        Devel::Declare->setup_for(
          $pack,
          { $name => { const => sub { $ctx_class->$parser($pack, @_) } } },
        );
      }
    }
    Sub::Exporter::default_installer(@_);

  }
};
# Where we store all the TCs for catch blocks created at compile time
# Not sure we really want to do this, but we will for now.
our $TC_LIBRARY = {};

sub check_tc {
  my ($class, $tc) = @_;

  my $type = $TC_LIBRARY->{$tc} or die "Unable to find parse TC for '$tc'";

  return $type->check($TryCatch::Error);
}

sub _string_to_tc {
  my ($class, $name) = @_;

  my $tc = $class->find_registered_constraint($name);

  return $tc if ref $tc;

  return Moose::Util::TypeConstraints::find_or_create_isa_type_constraint($name)
}

sub _parse_proto_impl {
  my ($self, $proto) = @_;

  my @conditions;

  my $sig = Parse::Method::Signatures->new(
    input => $proto,
    from_namespace => $self->get_curstash_name,
    type_constraint_callback => \&_string_to_tc,
  );
  my $errctx = $sig->ppi;
  my $param = $sig->param;

  $sig->error( $errctx, "Parameter expected")
    unless $param;

  my $left = $sig->remaining_input;

  my $var_code = '';

  if (my $var_name = $param->can('variable_name') ) {

    my $name = $param->$var_name();
    $var_code = "my $name = \$TryCatch::Error;";
  }

  # (TC $var)
  if ($param->has_type_constraints) {
    my $tc = $param->meta_type_constraint;
    $TryCatch::TC_LIBRARY->{"$tc"} = $tc;
    push @conditions, "TryCatch->check_tc('$tc')";
  }

  # ($var where { $_ } )
  if ($param->has_constraints) {
    foreach my $con (@{$param->constraints}) {
      $con =~ s/^{|}$//g;
      push @conditions, "do {local \$_ = \$TryCatch::Error; $con }";
    }
  }

  return $var_code, @conditions;
}

1;

__END__

=head1 NAME

TryCatch - first class try catch semantics for Perl, without source filters.

=head1 DESCRIPTION

This module aims to provide a nicer syntax and method to catch errors in Perl,
similar to what is found in other languages (such as Java, Python or C++).  The
standard method of using C<< eval {}; if ($@) {} >> is often prone to subtle
bugs, primarily that its far too easy to stomp on the error in error handlers.
And also eval/if isn't the nicest idiom.

=head1 SYNOPSIS

 use TryCatch;

 sub foo {
   my ($self) = @_;

   try {
     die Some::Class->new(code => 404 ) if $self->not_found;
     return "return value from foo";
   }
   catch (Some::Class $e where { $_->code > 100 } ) {
   }
 }

=head1 SYNTAX

This module aims to give first class exception handling to perl via 'try' and
'catch' keywords. The basic syntax this module provides is C<try { # block }>
followed by zero or more catch blocks. Each catch block has an optional type
constraint on it the resembles Perl6's method signatures.

Also worth noting is that the error variable (C<$@>) is localised to the
try/catch blocks and will not leak outside the scope, or stomp on a previous
value of C<$@>.

The simplest case of a catch block is just

 catch { ... }

where upon the error is available in the standard C<$@> variable and no type
checking is performed. The exception can instead be accessed via a named
lexical variable by providing a simple signature to the catch block as follows:

 catch ($err) { ... }

Type checking of the exception can be performed by specifying a type constraint
or where clauses in the signature as follows:

 catch (TypeFoo $e) { ... }
 catch (Dict[code => Int, message => Str] $err) { ... }

As shown in the above example, complex Moose types can be used, including
L<MooseX::Types> style of type constraints

In addition to type checking via Moose type constraints, you can also use where
clauses to only match a certain sub-condition on an error. For example,
assuming that C<HTTPError> is a suitably defined TC:

 catch (HTTPError $e where { $_->code >= 400 && $_->code <= 499 } ) {
   return "4XX error";
 }
 catch (HTTPError $e) {
   return "other http code";
 }

would return "4XX error" in the case of a 404 error, and "other http code" in
the case of a 302.

In the case where multiple catch blocks are present, the first one that matches
the type constraints (if any) will executed.

=head1 BENEFITS

B<return>. You can put a return in a try block, and it would do the right thing
- namely return a value from the subroutine you are in, instead of just from
the eval block.

B<Type Checking>. This is nothing you couldn't do manually yourself, it does it
for you using Moose type constraints.

=head1 TODO

=over

=item *

Decide on C<finally> semantics w.r.t return values.

=item *

Write some more documentation

=back

=head1 SEE ALSO

L<MooseX::Types>, L<Moose::Util::TypeConstraints>, L<Parse::Method::Signatures>,
L<TryCatch::Lite>.

=head1 AUTHOR

Ash Berlin <ash@cpan.org>

=head1 THANKS

Thanks to Matt S Trout and Florian Ragwitz for work on L<Devel::Declare> and
various B::Hooks modules

Vincent Pit for L<Scope::Upper> that makes the return from block possible.

Zefram for providing support and XS guidance.

Xavier Bergade for the impetus to finally fix this module in 5.12.

=head1 LICENSE

Licensed under the same terms as Perl itself.

