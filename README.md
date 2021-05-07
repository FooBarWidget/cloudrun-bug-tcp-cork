This is a sample which demonstrates a TCP\_CORK bug in Google Cloud Run.

> The bug has been reported to Google: [issue #187448830](https://issuetracker.google.com/issues/187448830)

Some HTTP servers — notably Ruby's [Puma](https://github.com/puma/puma) — optimize throughput by enabling TCP\_CORK on a client socket when writing a response. They only turn off TCP\_CORK when the response is complete.

[Server Sent Events](https://en.wikipedia.org/wiki/Server-sent_events) stream data to the client as events occur. There is normally no big problem combining TCP\_CORK with Server Sent Events, because according to Linux's [man 7 tcp](https://man7.org/linux/man-pages/man7/tcp.7.html), TCP\_CORK only corks output for at most 200ms.

However, Google Cloud Run's environment doesn't put a time limit on corking. Instead, it corks until the socket is uncorked.

## Reproducing the bug

The sample contains a simple custom-written HTTP 1.1 server, implemented in Ruby. It listens on port 0.0.0.0:9292 by default (customizable by setting the `PORT` environment variable).

When you call the `/events` path, it responds with a Server Sent Events stream that lasts for 5 seconds. Every 1 second, it sends an event containing a number.

### Setup (optional)

You can use the sample that I've already deployed on `https://cloudrun-bug-tcp-cork-true-f7awo4fcoa-uk.a.run.app/events`.

Or, if you want to deploy the sample yourself to Google Cloud Run:

~~~bash
gcloud run deploy \
	--platform=managed \
	--image=gcr.io/fullstaq-ruby/cloudrun-bug-tcp-cork:latest \
	--cpu=1 \
	--memory=256Mi \
	--max-instances=1 \
	--allow-unauthenticated \
	--region=us-east4 \
	--concurrency=1 \
	--set-env-vars=CORK=true \
	cloudrun-bug-tcp-cork-true
~~~

### Test

Send a request to the deployed sample...

~~~bash
curl -v https://cloudrun-bug-tcp-cork-true-f7awo4fcoa-uk.a.run.app/events
~~~

...and observe that it doesn't send events in real-time, but instead buffers all events until the request ends after 5 seconds.

## Reproducing expected behavior

We can reproduce the expected behavior in two ways:

 1. By running the sample on a regular Linux machine.
 2. By running the sample on Google Cloud Run, but disabling TCP\_CORK.

### Reproducing expected behavior on a regular Linux machine

Start a server:

~~~bash
# Use Docker:
docker run -ti --rm -p 9292:9292 gcr.io/fullstaq-ruby/cloudrun-bug-tcp-cork

# Or run the server directly without Docker (requires Ruby):
./myhttpserver.rb
~~~

We can see events being streamed in real-time:

~~~
$ curl -v http://127.0.0.1:9292/events
...events being streamed...
~~~

### Reproducing expected behavior on Google Cloud Run with TCP\_CORK disabled

The sample HTTP server will not cork sockets if we set the `CORK=false` environment variable.

I've deployed an instance that has corking disabled, on this address: `https://cloudrun-bug-tcp-cork-false-f7awo4fcoa-uk.a.run.app/events`.

Or, if you want to deploy it yourself:

~~~bash
gcloud run deploy \
	--platform=managed \
	--image=gcr.io/fullstaq-ruby/cloudrun-bug-tcp-cork:latest \
	--cpu=1 \
	--memory=256Mi \
	--max-instances=1 \
	--allow-unauthenticated \
	--region=us-east4 \
	--concurrency=1 \
	--set-env-vars=CORK=false \
	cloudrun-bug-tcp-cork-false
~~~

We can see events being streamed in real-time:

~~~
$ curl -v https://cloudrun-bug-tcp-cork-false-f7awo4fcoa-uk.a.run.app/events
...events being streamed...
~~~

### Additional remarks

*All* TCP sockets are affected, not just the HTTP client socket. So suppose that the container runs an Nginx reverse proxy, proxying to an app running on the same container but on another port. If the app sets TCP\_CORK on its HTTP client socket, then Nginx doesn't receive any response data until the app uncorks the socket.

Thus, this appears to be a kernel-level problem, rather than a network-level problem.
