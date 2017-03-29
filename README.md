# Networking

iOS networking library written in Swift

Setup: [How to add a Git repository to your Xcode project][1]

Usage:

Globally, e.g., at the top of `AppDelegate.swift`, do:

```swift
let api = API(baseURL: URL(string: "https://api.example.com"))
```

Let's define some local variables:

```swift
let email = "john.appleseed@example.com"
let fields = ["name": "John Appleseed", "email": email]
```

To make a GET request:

```swift
let request = api.request("GET", "/users")
```

To make a form POST request:

```swift
let request = api.request("POST", "/users", fields)
```

If certain API paths require an access token, set it:

```swift
api.accessToken = "fb2e77d.47a0479900504cb3ab4a1f626d174d2d"
```

To make an authenticated request, which includes your access token in the `Authorization` request header field:

```swift
let request = api.request("GET", "/me", authenticated: true)
```

To send any of the requests above, use `URLSession`:

```swift
let dataTask = URLSession.sharedSession().dataTask(with: request) { data, response, error in
    // Handle response
}
```

For help parsing a JSON response and converting an unsuccessful status code into an `error`, use `API`:

```swift
let dataTask = api.dataTask(with: request) { object, response, error in
    // Handle response
}
```

To make and send a multipart (file-upload) request:

```swift
let JPEGData = UIImageJPEGRepresentation(UIImage(named: "JohnAppleseed"), 0.9)
let request = api.request("POST", "/users", fields, JPEGData)
let dataTask = URLSession.sharedSession().uploadTaskWithRequest(request, fromData: request.HTTPBody!) { data, response, error in
    // Handle response
}
```

Use `HTTP` instead of `api` for making one-off requests to resources with different base URLs.

See the [Acani Chats iPhone Client][2] for example usage.

See [`Networking.swift`][3] for other handy functions not mentioned here.

Released under the [Unlicense][4].


  [1]: https://github.com/acani/Libraries
  [2]: https://github.com/acani/Chats-iPhone-Client
  [3]: https://github.com/acani/Networking/blob/master/Networking.swift
  [4]: http://unlicense.org
