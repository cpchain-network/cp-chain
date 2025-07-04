// Code generated by mockery v2.28.1. DO NOT EDIT.

package mocks

import (
	context "context"
	http "net/http"

	mock "github.com/stretchr/testify/mock"

	url "net/url"
)

// HTTP is an autogenerated mock type for the HTTP type
type HTTP struct {
	mock.Mock
}

type HTTP_Expecter struct {
	mock *mock.Mock
}

func (_m *HTTP) EXPECT() *HTTP_Expecter {
	return &HTTP_Expecter{mock: &_m.Mock}
}

// Get provides a mock function with given fields: ctx, path, query, headers
func (_m *HTTP) Get(ctx context.Context, path string, query url.Values, headers http.Header) (*http.Response, error) {
	ret := _m.Called(ctx, path, query, headers)

	var r0 *http.Response
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, string, url.Values, http.Header) (*http.Response, error)); ok {
		return rf(ctx, path, query, headers)
	}
	if rf, ok := ret.Get(0).(func(context.Context, string, url.Values, http.Header) *http.Response); ok {
		r0 = rf(ctx, path, query, headers)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*http.Response)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, string, url.Values, http.Header) error); ok {
		r1 = rf(ctx, path, query, headers)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// HTTP_Get_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'Get'
type HTTP_Get_Call struct {
	*mock.Call
}

// Get is a helper method to define mock.On call
//   - ctx context.Context
//   - path string
//   - query url.Values
//   - headers http.Header
func (_e *HTTP_Expecter) Get(ctx interface{}, path interface{}, query interface{}, headers interface{}) *HTTP_Get_Call {
	return &HTTP_Get_Call{Call: _e.mock.On("Get", ctx, path, query, headers)}
}

func (_c *HTTP_Get_Call) Run(run func(ctx context.Context, path string, query url.Values, headers http.Header)) *HTTP_Get_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context), args[1].(string), args[2].(url.Values), args[3].(http.Header))
	})
	return _c
}

func (_c *HTTP_Get_Call) Return(_a0 *http.Response, _a1 error) *HTTP_Get_Call {
	_c.Call.Return(_a0, _a1)
	return _c
}

func (_c *HTTP_Get_Call) RunAndReturn(run func(context.Context, string, url.Values, http.Header) (*http.Response, error)) *HTTP_Get_Call {
	_c.Call.Return(run)
	return _c
}

type mockConstructorTestingTNewHTTP interface {
	mock.TestingT
	Cleanup(func())
}

// NewHTTP creates a new instance of HTTP. It also registers a testing interfaces on the mock and a cleanup function to assert the mocks expectations.
func NewHTTP(t mockConstructorTestingTNewHTTP) *HTTP {
	mock := &HTTP{}
	mock.Mock.Test(t)

	t.Cleanup(func() { mock.AssertExpectations(t) })

	return mock
}
