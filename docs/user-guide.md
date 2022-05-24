# isc.rest User Guide

For a step-by-step tutorial, see [isc.rest Tutorial and Sample Application: Contact List](sample-phonebook.md).

## Prerequisites

isc.rest requires InterSystems IRIS Data Platform 2018.1 or later.

Installation is done via the [Community Package Manager](https://github.com/intersystems-community/zpm):

    zpm "install isc.rest"

## Getting Started

### Create and Configure a REST Handler

Create a subclass of `%pkg.isc.rest.handler`. `%pkg.isc.rest.handler` extends `%CSP.REST`, and for the most part this subclass may include overrides the same as a subclass of %CSP.REST.

For example, a user may add overrides to use the following %CSP.REST features:

* The `UseSession` class parameter if CSP sessions should be used (by default, they are not, as CSP sessions are not stateless).
* CORS-related parameters and methods if CORS support is required. (Use this carefully and with knowledge of the security implications!)

However, **do not override the UrlMap XData block**; the routes are standardized and you should not need to edit/amend them.

To augment an existing REST API with isc.rest features, forward a URL from your existing REST handler to this subclass of `%pkg.isc.rest.handler`.

To create a new isc.rest-based REST API, configure the subclass of `%pkg.isc.rest.handler` as the Dispatch Class for a new web application.

### Define an Authentication Strategy

If the web application uses password or delegated authentication, simply override the AuthenticationStrategy() method in the REST handler class as follows:

    ClassMethod AuthenticationStrategy() As %Dictionary.CacheClassname
    {
        Quit "%pkg.isc.rest.authentication.platformBased"
    }

If not (for example, because of a more complex token-based approach such as OAuth that does not use delegated authentication/authorization), create a subclass of `%pkg.isc.rest.authentication` and override the `Authenticate`, `UserInfo`, and `Logout` methods as appropriate.
For example, `Authenticate` might check for a bearer token and set `pContinue` to false if one is not present; `UserInfo` may return an OpenID Connect "userinfo" object, and `Logout` may invalidate/revoke an access token. In this case, the `AuthenticationStrategy` method in the `%pkg.isc.rest.handler` subclass should return the name of the class implementing the authentication strategy.

### Define a User Resource

If the application already has a class representing the user model, preferences, etc., consider providing a REST model for it as described below. Alternatively, for simple use cases, you may find it helpful to wrap platform security features in a registered object; see [UnitTest.isc.rest.sample.userContext](https://github.com/intersystems/isc-rest/blob/master/internal/testing/unit_tests/UnitTest/isc/rest/sample/userContext.cls) for an example of this.

In either approach, the `GetUserResource` method in the application's `%pkg.isc.rest.handler` subclass should be overridden to return a new instance of this user model. For example:

    ClassMethod GetUserResource(pFullUserInfo As %DynamicObject) As UnitTest.isc.rest.sample.userContext
    {
        Quit ##class(UnitTest.isc.rest.sample.userContext).%New()
    }

### Authentication-related Endpoints

HTTP Verb + Endpoint|Function
---|---
GET&nbsp;/auth/status|Returns information about the currently-logged-in user, if the user is authenticated, or an HTTP 401 if the user is not authenticated and authentication is required.
POST&nbsp;/auth/logout|Invokes the authentication strategy's Logout method. (No body expected.)

## Defining REST Models

isc.rest provides for standardized access to both persistent data and business logic.

### Accessing Data: Adaptor vs. Proxy

There are two different approaches to exposing persistent data over REST. The "Adaptor" approach provides a single REST representation for the existing `%Persistent` class. The "Proxy" approach provides a REST representation for a *different* `Persistent` class.

#### %pkg.isc.rest.model.adaptor

To expose data of a class that extends %Persistent over REST, simply extend `%pkg.isc.rest.model.adaptor` as well. Then, override the following class parameters:

* `RESOURCENAME`: Set this to the URL prefix you want to use for the resource in a REST context (e.g., "person")
* `JSONMAPPING` (optional): Defaults to empty (the class's default JSON mapping); set this to the name of a JSON mapping XData block
* `MEDIATYPE` (optional): Defaults to "application/json"; may be overridden to specify a different media type (e.g., application/vnd.yourcompany.v1+json; should still be an application/json subtype)

For an example of using `%pkg.isc.rest.model.adaptor`, see: [UnitTest.isc.rest.sample.data.vendor](https://github.com/intersystems/isc-rest/blob/master/internal/testing/unit_tests/UnitTest/isc/rest/sample/data/vendor.cls)

#### %pkg.isc.rest.model.proxy

To expose data of a *different* class that extends %Persistent over REST, perhaps using an alternative JSON mapping from other projections of the same data, extend `%pkg.isc.rest.model.proxy`. In addition to the same parameters as `%pkg.isc.rest.model.adaptor`, you must also override the `SOURCECLASS` parameter to specify a different class that extends both `%pkg.isc.json.adaptor` and `%Persistent`.

For an example of using %pkg.isc.rest.model.proxy, see: [UnitTest.isc.rest.sample.model.person](https://github.com/intersystems/isc-rest/blob/master/internal/testing/unit_tests/UnitTest/isc/rest/sample/model/person.cls)

### Permissions

Whether you extend `adaptor` or `proxy`, you must override the `CheckPermissions` method, which by default says that nothing is allowed:

    /// Checks the user's permission for a particular operation on a particular record.
    /// <var>pOperation</var> may be one of:
    /// CREATE
    /// READ
    /// UPDATE
    /// DELETE
    /// QUERY
    /// ACTION:<action name>
    /// <var>pUserContext</var> is supplied by <method>GetUserContext</method>
    ClassMethod CheckPermission(pID As %String, pOperation As %String, pUserContext As %RegisteredObject) As %Boolean
    {
        Quit 0
    }

`pUserContext` is an instance of the user resource defined earlier.

### CRUD and Query Endpoints

With resources defined as described above, the following endpoints are available:

HTTP&nbsp;Verb&nbsp;/&nbsp;Endpoint|Function
---|---
GET&nbsp;/:resource | Returns an array of instances of the requested resource, subject to filtering criteria specified by URL parameters.
POST&nbsp;/:resource | Saves a new instance of the specified resource (present in the request entity body) in the database. Responds with the JSON representation of the resource, including a newly-assigned ID, if relevant, as well as any fields populated when the record was saved.
GET&nbsp;/:resource/:id | Retrieves an instance of the resource with the specified ID
PUT&nbsp;/:resource/:id | Updates the specified instance of the resource in the database (based on ID, with the data present in the request entity body). Responds with the JSON representation of the resource, including any fields updated when the record was saved.​
DELETE&nbsp;/:resource/:id | Deletes the instance of the resource with the specified ID

### Actions

"Actions" allow you to provide a REST projection of business logic (that is, ObjectScript methods and classmethods) and class queries (abstractions of more complex SQL) alongside the basic REST capabilities. To start, override the `Actions` XData block:

    XData ActionMap [ XMLNamespace = "http://www.intersystems.com/_pkg/isc/rest/action" ]
    {
    }

 Note - Studio will help with code completion for XML in this namespace.

[UnitTest.isc.rest.sample.model.person](https://github.com/intersystems/isc-rest/blob/master/internal/testing/unit_tests/UnitTest/isc/rest/sample/model/person.cls) has annotated examples covering the full range of action capabilities. As a general guideline, do ensure that the HTTP verb matches the behavior of the endpoint (e.g., PUT and DELETE are idempotent, GET is safe, POST is neither).

#### Action Endpoints

HTTP&nbsp;Verbs&nbsp;+&nbsp;Endpoint|Function
---|---
GET,&nbsp;PUT,&nbsp;POST,&nbsp;DELETE&nbsp;/:resource/$:action|Performs the named action on the specified resource. Constraints and format of URL parameters, body, and response contents will vary from action to action, but are well-defined.
GET,&nbsp;PUT,&nbsp;POST,&nbsp;DELETE&nbsp;/:resource/:id/$:action|Performs the named action on the specified resource instance. Constraints and format of URL parameters, body, and response contents will vary from action to action, but are well-defined.

## Related Topics in InterSystems Documentation

* [Using the JSON Adaptor](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GJSON_adaptor)
* [Introduction to Creating REST Services](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GREST_intro)
* [Supporting CORS in REST Services](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GREST_cors)
* [Securing REST Services](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GREST_securing)
