package main

type List[T any] struct {
	items []T
}

func (l *List[T]) Len() int {
	return len(l.items)
}

type Pair[K comparable, V any] struct {
	Key   K
	Value V
}
