/// Load lifecycle shared by every slice.
///
/// Screens map this straight onto skeleton / content / error-with-retry, which
/// is why every list-bearing slice carries one.
enum Status {
  idle,
  loading,
  ready,
  error;

  bool get isLoading => this == Status.loading || this == Status.idle;

  bool get isError => this == Status.error;

  bool get isReady => this == Status.ready;
}
