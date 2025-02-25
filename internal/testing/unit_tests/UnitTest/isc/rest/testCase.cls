/// isc.rest Unit Test "base" class from which each app developer can build a (potential hierarchy of)
/// Unit Tests for that app.
/// Provide convenience functions to support the testing of REST dispatcher methods.
/// Should be an abstract class, but can't be because it's in the unit test root and %UnitTest.Manager will try to run it.
Class UnitTest.isc.rest.testCase Extends HSTools.UnitTest.Mock.TestCase
{

/// Subclasses must override this parameter to define the application's REST handler class that is to be tested.
Parameter RESTHandlerClass As CLASSNAME [ Abstract ];

Parameter MediaType As STRING = "application/json";

/// Defines the class used as the "user" in the app
Parameter RequesterClass As CLASSNAME [ Abstract ];

/// The id of the User making this REST request.  May be overriden by subclasses, although the actual value
/// of RequesterId is irrelevant if it's referred to throughout the test using ..#RequesterId.
Parameter RequesterId As STRING = "RequesterId";

/// The id of the resource you're looking for, used to test URL's that require an id (ex: get, put, delete).
/// Like with RequesterId, the actual value of TestId is irrelevant if it's referred to using ..#TestId.
Parameter TestId As STRING = "TestId";

/// Subclasses should override this
Parameter RESOURCENAME As STRING;

/// Specify the name of a class with generated code.  This will be compiled as part of the test.
Parameter ClassToCompile As STRING;

/// The contents of this Dynamic Object will be written to the body of the test POST request.
Property BodyForTestPOST As %DynamicAbstractObject;

/// The contents of this Dynamic Object will be written to the body of the test PUT request.
Property BodyForTestPUT As %DynamicAbstractObject;

/// Set to 1 while debugging a unit test, so that you see the error message, instead of just "response was http 500"
Parameter ThrowExceptionInsteadOfHttp500 = 0;

/// abstract GetMockUserResource method that can be overridden in subclasses
Method GetMockUserResource(pCall As HSTools.UnitTest.Mock.MethodCall, pArguments...) As %pkg.isc.rest.model.resource [ Abstract ]
{
}

/// another abstract method that should be overridden in subclasses to support the generated code in MockAuthentication
Method GetMockUserInfo(pCall As HSTools.UnitTest.Mock.MethodCall, pArguments...) As %Status [ Abstract ]
{
}

/// another abstract method that should be overridden in subclasses to support the generated code in MockAuthentication
Method MockSSOGUIDIndexOpen(pCall As HSTools.UnitTest.Mock.MethodCall, pArguments...) As %pkg.isc.rest.model.resource [ Abstract ]
{
}

/// Set up any mocks necessary for mocking behavior during the handling of a GET, POST, PUT, or DELETE request.
Method ConfigureMocking()
{
	do ..MockAuthentication()
}

/// Forms a mock HTTP request and sends it to the handler.  Returns the response object, as well as the 
/// content from the response body as both a json dynamic object, and as a string.
Method Request(pVerb As %String, pRoute As %String, ByRef pRequest As %CSP.Request, Output pResponse As %CSP.Response = {$$$NULLOREF}, Output pJSONContent As %DynamicAbstractObject, Output pRawContent As %String)
{
	New %request,%response,%session
	Set %request = $Get(pRequest, ##class(%CSP.Request).%New())
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New($System.Encryption.GenCryptRand(8))
	Set pJSONContent = $$$NULLOREF
	Set pRawContent = ""
	
	If (%request.Method = "") {
		Set %request.Method = pVerb
	}
	
	Set buffer = ##class(%pkg.isc.json.util.buffer).%New()
	Set sc = buffer.BeginCaptureOutput()
	$$$ThrowOnError(sc)
	If $Extract(pRoute) = "/" {
		Set pRoute = $Extract(pRoute,2,*)
	}
	
	// Try/Catch and error handling matches %CSP.REST:Page behavior
	Try {
		// Use $parameter($this) rather than ..# to avoid compilation errors in non-abstract subclasses
		Set tSC = $classmethod($parameter($this,"RESTHandlerClass"),"DispatchRequest",pRoute,pVerb)
		$$$ThrowOnError(tSC)
	} Catch (e) {
		Set tSC =e.AsStatus()
	}
	If $$$ISERR(tSC) {
		#; Don't want the session token
		if (..#ThrowExceptionInsteadOfHttp500){
			$$$ThrowOnError(tSC)
		}
		Set %response.OutputSessionToken=0
		Do $classmethod($parameter($this,"RESTHandlerClass"),"Http500",##class(%Exception.StatusException).CreateFromStatus(tSC))
	}
    // End simulation of %CSP.REST:Page
    
	Set sc3 = buffer.EndCaptureOutput(.pRawContent)
	$$$ThrowOnError(sc3)
	
	Set pResponse = %response
	
	If (pRawContent '= "") && (%response.ContentType [ "json") {
		Set pJSONContent = ##class(%DynamicAbstractObject).%FromJSON(pRawContent)
	}
}

Method MockAuthentication() [ CodeMode = objectgenerator ]
{
	If (%class.Name = "UnitTest.isc.rest.testCase") || (%class.Abstract) {
		Quit $$$OK
	}
	// All methods testing REST service calls will "log-in" via mock means
	// Get the OAuth2Class for the REST Handler being tested
	Set handler = %parameter("RESTHandlerClass")
	If (handler = "") {
		Quit $$$ERROR($$$GeneralError,"Must define RESTHandlerClass parameter in class "_%class.Name)
	}
	Set oauthClass = $parameter(handler,"OAuth2Class")
	If (oauthClass = "") {
		set oauthClass = $classmethod(handler,"AuthenticationStrategy") //TODO: refactor this class to mock Authentication interface
		If (oauthClass = "") {
			Quit $$$ERROR($$$GeneralError,"OAuth2Class parameter not defined in "_handler)
		}
	}

	// Get the "user class" for the REST Handler being tested
	Set requester = %parameter("RequesterClass")
	If (requester = "") {
		Quit $$$ERROR($$$GeneralError,"Must define RequesterClass parameter in class "_%class.Name)
	}	
	// Mock authentication
	Do %code.WriteLine(" Do ..mockStatic("_$$$QUOTE(oauthClass)_")")
	Do %code.WriteLine(" Do ..when(##class("_oauthClass_").UserInfo(..optional())).thenAnswer(..withMethod($this,""GetMockUserInfo""))")
	If $System.CLS.IsMthd(oauthClass,"CheckPermission") {
		Do %code.WriteLine(" Do ..when(##class("_oauthClass_").CheckPermission(..optional(3))).thenInvokeRealMethod()")	
	}
	// Partial mock to stub GetUserResource *only* in the REST handler
	Do %code.WriteLine(" Do ..mockStatic("_$$$QUOTE(handler)_",..#CALLSREALMETHODS)")
	Do %code.WriteLine(" Do ..when(##class("_handler_").GetUserResource(..#RequesterId,..optional(1))).thenAnswer(..withMethod($this,""GetMockUserResource""))")
	
	// More mocking to handle the potential look ups of "users" by SSOGUID
	Do %code.WriteLine(" Do ..mockStatic("_$$$QUOTE(requester)_",..#CALLSREALMETHODS)")	
	Do %code.WriteLine(" Do ..when(##class("_requester_").SSOGUIDIndexExists(..#RequesterId)).thenReturn(1)")
	Do %code.WriteLine(" Do ..when(##class("_requester_").SSOGUIDIndexOpen(..#RequesterId,..optional(2))).thenAnswer(..withMethod($this,""MockSSOGUIDIndexOpen""))")
	Do %code.WriteLine(" Do ..when(##class("_requester_").GetModelInstance(..optional())).thenAnswer(..withMethod($this,""MockSSOGUIDIndexOpen""))")
	Do %code.WriteLine(" Quit")
	
	Quit $$$OK
}

/// This code will be run immediately after the GET request is processed. <br><br>
/// <b>response</b> - The <class>%CSP.Response</class> object returned by the request. <br>
/// <b>json</b> - The response payload, as a <class>%DynamicAbstractObject</class>. <br>
/// <b>rawContent</b> - The raw, <class>%String</class> representation of the response payload. <br><br>
/// This method should be overwritten to assert based on the response, json, or rawContent.  You can also
/// add write statements to add more detail to the test output.  By default, this method will assert
/// that the request returned a 403 forbidden.
Method AssertAfterGET(response As %CSP.Response, json As %DynamicAbstractObject, rawContent As %String)
{
	do $$$AssertEquals(response.Status, ##class(%CSP.REST).#HTTP403FORBIDDEN)
}

/// This code will be run immediately after the GET PL request is processed. <br><br>
/// <b>response</b> - The <class>%CSP.Response</class> object returned by the request. <br>
/// <b>json</b> - The response payload, as a <class>%DynamicAbstractObject</class>. <br>
/// <b>rawContent</b> - The raw, <class>%String</class> representation of the response payload. <br><br>
/// This method should be overwritten to assert based on the response, json, or rawContent.  You can also
/// add write statements to add more detail to the test output.  By default, this method will assert
/// that the request returned a 403 forbidden.
Method AssertAfterGETPL(response As %CSP.Response, json As %DynamicAbstractObject, rawContent As %String)
{
	do $$$AssertEquals(response.Status, ##class(%CSP.REST).#HTTP403FORBIDDEN)
}

/// This code will be run immediately after the POST request is processed. <br><br>
/// <b>response</b> - The <class>%CSP.Response</class> object returned by the request. <br>
/// <b>json</b> - The response payload, as a <class>%DynamicAbstractObject</class>. <br>
/// <b>rawContent</b> - The raw, <class>%String</class> representation of the response payload. <br><br>
/// This method should be overwritten to assert based on the response, json, or rawContent.  You can also
/// add write statements to add more detail to the test output.  By default, this method will assert
/// that the request returned a 403 forbidden.
Method AssertAfterPOST(response As %CSP.Response, json As %DynamicAbstractObject, rawContent As %String)
{
	do $$$AssertEquals(response.Status, ##class(%CSP.REST).#HTTP403FORBIDDEN)
}

/// This code will be run immediately after the PUT request is processed. <br><br>
/// <b>response</b> - The <class>%CSP.Response</class> object returned by the request. <br>
/// <b>json</b> - The response payload, as a <class>%DynamicAbstractObject</class>. <br>
/// <b>rawContent</b> - The raw, <class>%String</class> representation of the response payload. <br><br>
/// This method should be overwritten to assert based on the response, json, or rawContent.  You can also
/// add write statements to add more detail to the test output.  By default, this method will assert
/// that the request returned a 403 forbidden.
Method AssertAfterPUT(response As %CSP.Response, json As %DynamicAbstractObject, rawContent As %String)
{
	do $$$AssertEquals(response.Status, ##class(%CSP.REST).#HTTP403FORBIDDEN)
}

/// This code will be run immediately after the DELETE request is processed. <br><br>
/// <b>response</b> - The <class>%CSP.Response</class> object returned by the request. <br>
/// <b>json</b> - The response payload, as a <class>%DynamicAbstractObject</class>. <br>
/// <b>rawContent</b> - The raw, <class>%String</class> representation of the response payload. <br><br>
/// This method should be overwritten to assert based on the response, json, or rawContent.  You can also
/// add write statements to add more detail to the test output.  By default, this method will assert
/// that the request returned a 403 forbidden.
Method AssertAfterDELETE(response As %CSP.Response, json As %DynamicAbstractObject, rawContent As %String)
{
	do $$$AssertEquals(response.Status, ##class(%CSP.REST).#HTTP403FORBIDDEN)
}

Method RunTestForEachVerb(message, URLParams)
{
	if (..#ClassToCompile '=""){
		write !, "--------------------------------------------"
		write !, "Testing "_..#ClassToCompile_"'s generated code compiles"
		write !, "--------------------------------------------"
		Do $$$AssertStatusOK($System.OBJ.Compile(..#ClassToCompile,"ck/multicompile=0"))
	}
	
	write !,"-------------------------------------------------"
	write !,"** Running tests for the /"_..#RESOURCENAME_" endpoint."
	write !,"** Using media-type: "_..#MediaType
	write:($g(message)'="") !,"** "_message
	write !,"-------------------------------------------------"

	
	do ..ConfigureMocking()
	
	kill get, post, put, delete, getpl
	
	merge get = URLParams("GET")
	merge post = URLParams("POST")
	merge put = URLParams("PUT")
	merge delete = URLParams("DELETE")
	merge getpl = URLParams("GETPL")
	
	do ..RunTestForVerb("GET", .get)
	do ..RunTestForVerb("POST", .post)
	do ..RunTestForVerb("PUT", .put)
	do ..RunTestForVerb("DELETE", .delete)
	do ..RunTestForVerb("GETPL", .getpl)
}

Method RunTestForVerb(pVerb, ByRef pURLParams)
{
	// Informative write that the test is happening
	write !,"--------------------------"
	write !, "*** Testing "_pVerb_"  ***"
	write !,"--------------------------"
	
	kill request, response, json, rawContent
	
	// Configure the test request
	#dim request As %CSP.Request
	set request = ..mock("%CSP.Request",..#CALLSREALMETHODS)
	do request.InsertCgiEnv("HTTP_ACCEPT",..#MediaType)
	
	//TODO: Investigate: Why do we need to set this for DELETE to work??
	set request.ContentType = ..#MediaType
	
	// For some requests, we have to configure the request body
	if ((pVerb = "PUT") || (pVerb = "POST")){
		
		write !, "Configuring "_pVerb_" request body..."
		
		set request.Content = ##class(%CSP.CharacterStream).%New()
		set body = $property($this, "BodyForTest"_pVerb)
		set:('$IsObject(body)) body = {}
		do body.%ToJSON(request.Content)
	}
	
	// For some requests, we append the TestId after the resource name in the route
	set routeAfterResource = "/"_..#RESOURCENAME
	if ((pVerb="GET") || (pVerb="PUT") || (pVerb = "DELETE")){
		set routeAfterResource = routeAfterResource_"/"_..#TestId
	}
	
	merge request.Data = pURLParams
	
	set verb = pVerb
	set:(pVerb="GETPL") verb = "GET"
	
	do ..Request(verb,routeAfterResource,request,.response,.json,.rawContent)

	do $method($this, "AssertAfter"_pVerb, .response, .json, .rawContent)
}

}

