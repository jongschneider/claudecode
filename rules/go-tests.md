---
globs: "*_test.go"
---

Use `stretchr/testify` (`assert` and `require` packages). Use table-driven tests.

## Table-driven test fields

- `assert func(t *testing.T, <resultType>)` — validates output. Always called, never nil, never a no-op.
- `assertError func(t *testing.T, err error)` — validates errors. Always called, never nil, never a no-op.
- `assertMock func(t *testing.T, m <mockTypes>...)` — validates mock interactions. When mocks are in use, always called, never nil, never a no-op.

Include `assert` when there is a result to validate. Include `assertError` when the code path produces an error. Include `assertMock` when mocks are used. When present, all three must be non-nil, non-no-op, and always called.
