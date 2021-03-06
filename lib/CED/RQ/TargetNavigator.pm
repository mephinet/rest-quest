package CED::RQ::TargetNavigator;

use Moose;
use Hash::PriorityQueue;

use CED::RQ::PathItem;

use namespace::autoclean;

extends 'CED::RQ::Navigator';

has 'target', is => 'ro', isa => 'CED::RQ::Tile', required => 1;
has '_last_map_revision', is => 'rw', isa => 'Int', default => -1;
has '_current_path', is => 'rw', isa => 'Maybe[CED::RQ::PathItem]';
has '_current', is => 'rw', isa => 'CED::RQ::Tile';
has '_search_fallback', is => 'ro', isa => 'CED::RQ::SearchNavigator',
    lazy => 1, builder => '_build__search_fallback';

sub _build__search_fallback {
    my ($self) = @_;
    return CED::RQ::SearchNavigator->new(map => $self->map);
}

sub _dist {
    my ($self, $tile, $target) = @_;

    my $dist_x = abs($target->x - $tile->x);
    if ($self->map->size_x) {
        my $dist_x_wrapped = abs(($target->x + $self->map->size_x) - $tile->x);
        $dist_x = $dist_x_wrapped if $dist_x_wrapped < $dist_x;
    }
    my $dist_y = abs($target->y - $tile->y);
    if ($self->map->size_y) {
        my $dist_y_wrapped = abs(($target->y + $self->map->size_y) - $tile->y);
        $dist_y = $dist_y_wrapped if $dist_y_wrapped < $dist_y;
    }
    return $dist_x + $dist_y;
}

sub _find_path {
    my ($self) = @_;

    $self->_last_map_revision($self->map->revision);
    $self->_current($self->map->current);
    my $q = Hash::PriorityQueue->new();

    my %seen;
    my $first_item = CED::RQ::PathItem->new(
        start => $self->map->current,
        tile => $self->map->current,
        min_possible_len => $self->_dist($self->map->current, $self->target)
        );
    $q->insert($first_item, $first_item->min_possible_len);
    while (1) {
        my $item = $q->pop();
        return unless $item;
        return $item if ($item->tile->key eq $self->target->key);

        $seen{$item->tile->key} = 1;
        foreach (qw/up down left right/) {
            my $edge = $item->tile->$_;
            next unless $edge;
            next if ($edge->target->deadly);
            next if ($seen{$edge->target->key});
            my $dist =
                $self->_dist($edge->target, $self->target) + $edge->overhead;

            my $new_item = CED::RQ::PathItem->new(
                start => $item->start,
                min_possible_len => $dist,
                tile => $edge->target,
                path => [@{$item->path}, $_]
                );
            $q->insert($new_item, $new_item->min_possible_len);
        }
    }
    return;
}

sub calc_move {
    my ($self) = @_;

    $self->_current_path($self->_find_path())
        if (!$self->_current_path ||
            ($self->_last_map_revision != $self->map->revision) ||
            ($self->_current->key ne $self->map->current->key));
    if ($self->_current_path) {
        return $self->_current_path->path->[0];
    } else {
        return $self->_search_fallback->calc_move();
    }
}

sub distance_to_target {
    my ($self) = @_;

    $self->_current_path($self->_find_path())
        if (!$self->_current_path ||
            ($self->_last_map_revision != $self->map->revision) ||
            ($self->_current->key ne $self->map->current->key));
    return $self->_current_path && $self->_current_path->min_possible_len;
}

sub consume {
    my ($self, $direction) = @_;

    $self->_current_path->consume($direction);
    $self->_current($self->_current->$direction->target);
}

__PACKAGE__->meta->make_immutable();

1
