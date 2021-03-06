module temple.vibe;

version(Have_vibe_d):

pragma(msg, "Compiling Temple with Vibed support");

private {
	import temple.temple;
	import vibe.http.server;
	import vibe.textfilter.html;
	import std.stdio;
}

struct TempleHtmlFilter {

	private static struct SafeString {
		const string payload;
	}

	static void templeFilter(OutputStream stream, string unsafe) {
		filterHTMLEscape(stream, unsafe);
	}

	static string templeFilter(SafeString safe) {
		return safe.payload;
	}

	static SafeString safe(string str) {
		return SafeString(str);
	}
}

private enum SetupContext = q{
	static if(is(Ctx == HTTPServerRequest)) {
		TempleContext context = new TempleContext();
		copyContextParams(context, req);
	}
	else {
		TempleContext context = req;
	}
};

private template isSupportedCtx(Ctx) {
	enum isSupportedCtx = is(Ctx : HTTPServerRequest) || is(Ctx == TempleContext);
}

void renderTemple(string temple, Ctx = TempleContext)
	(HTTPServerResponse res, Ctx req = null)
	if(isSupportedCtx!Ctx)
{
	mixin(SetupContext);

	alias render = Temple!(temple, TempleHtmlFilter);
	render(res.bodyWriter, context);
}

void renderTempleFile(string file, Ctx = TempleContext)
	(HTTPServerResponse res, Ctx req = null)
	if(isSupportedCtx!Ctx)
{
	mixin(SetupContext);

	alias render = TempleFile!(file, TempleHtmlFilter);
	render(res.bodyWriter, context);
}

void renderTempleLayoutFile(string layout_file, string partial_file, Ctx = TempleContext)
	(HTTPServerResponse res, Ctx req = null)
	if(isSupportedCtx!Ctx)
{
	mixin(SetupContext);

	alias layout = TempleLayoutFile!(layout_file, TempleHtmlFilter);
	alias partial = TempleFile!(partial_file, TempleHtmlFilter);

	layout(res.bodyWriter, &partial, context);
}

private void copyContextParams(ref TempleContext ctx, ref HTTPServerRequest req) {

	if(!req || !(req.params))
		return;

	foreach(key, val; req.params) {
		ctx[key] = val;
	}
}
