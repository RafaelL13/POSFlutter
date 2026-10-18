// SQL Server integration tests create and delete isolated databases on one
// LocalDB instance. Running them concurrently can leave schema operations
// blocked long enough for otherwise unrelated report queries to time out.
[assembly: Xunit.v3.Parallelization(Mode = Xunit.Sdk.ParallelMode.None)]
