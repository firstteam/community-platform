package DDGC::Search::Client;

use Moose;
use Dezi::Doc;
use DDGC::Config;
use HTML::Strip;
use JSON 'encode_json';

use MooseX::NonMoose;
extends 'Dezi::Client';

sub FOREIGNBUILDARGS {
    my $class = shift;
    my %args  = @_;

    my $server = $args{ddgc}->config->dezi_uri . '/' . $args{type} . '/';

    return (server => $server, search => 'search', index => 'index');
};

has type => (
    is => 'ro',
    required => 1,
);

has ddgc => (
    is => 'ro',
    required => 1,
    weak_ref => 1,
);

has stripper => (
    is => 'ro',
    lazy_build => 1,
);

sub _build_stripper {
    HTML::Strip->new
}

sub resultset {
    my ($self, $c, $query, $rs, %args) = @_;
    die 'resultset() needs $c, $query, $rs.' unless defined $c || defined $query || defined $rs;

    my $result = $self->search(q => $query, %args // ());

    my %results;
    my $resultset;
    my $order_by;
    # This will become:
    # CASE id
    #   WHEN x THEN i
    #   ELSE last_i+1
    # END
    # With an additional when line for each x (id) in results.
    # It is used as the ORDER BY clause to retain the search
    # engine's ranking.
    my $case = "CASE id";

    if ($result && $result->total) {
        my @ids;
        push @ids, $_->get_field('id')->[0] for @{$result->results};

        $results{$_->get_field('id')->[0]} = $_ for @{$result->results};
        my $i;

        $case .= ' WHEN '.$_.' THEN '.++$i for @ids;
        $case .= ' ELSE '.++$i.' END, id';

        $order_by = \do { $case };
        
        $resultset = $rs->search_rs({id => \@ids},
            { order_by => {
                  -desc => $order_by
                }
        });

        if (my $ducky = $c->req->param('ducky')) {
            my $first = $resultset->first;
            if (defined $first && $first->can('u')) {
                $c->response->redirect($c->chained_uri(@{$first->u}));
                return $c->detach;
            }
        }
    }

    return \%results, $resultset, $order_by;
}

sub rs { shift->resultset(@_) }

around index => sub {
    my ($orig, $self) = (shift, shift);
    return $self->$orig(@_) if ref $_[0] eq 'Dezi::Doc';

    my %args = @_;
    my $is_markup = defined $args{is_markup} ? delete $args{is_markup} : 0;
    my $is_html = defined $args{is_html} ? delete $args{is_html} : 0;
    my $uri = delete $args{uri};

    if ($is_markup && defined $args{body}) {
        $args{body} = $self->ddgc->markup->plain($args{body});
    }
    elsif ($is_html && defined $args{body}) {
        $args{body} = $self->stripper->parse($args{body});
        $self->stripper->eof;
    }

    my $doc = encode_json({
        mtime => time,
        content_type => 'application/json',
        %args,
    });

    return $self->$orig(
        \$doc,
        $uri,
        'application/json',
    );
};


__PACKAGE__->meta->make_immutable;
1;

# ABSTRACT: A Dezi-based search/indexing abstraction

__DATA__

=pod

=head1 SYNOPSIS

    my $search = DDGC::Search::Client->new(
        ddgc => $ddgc,
        type => 'foo',
    );

    $search->index(
        title   => "I am a document",
        body => "... and this is my body.",
    );

    my $response = $search->search( q => "document" );

B<$response> is a L<Dezi::Response>.

=head1 DESCRIPTION

This is the client part of DDGC's search engine abstraction layer. It inherits L<Dezi::Client>.

=head1 OVERRIDDEN METHODS

=over 4

=item B<index(%data)>

This method takes a hash of options which will be encoded to JSON and passed to L<Dezi::Client>.

=back

=cut
