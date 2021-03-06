/**
 * Temple (C) Dylan Knutson, 2013, distributed under the:
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 */

module temple.func_string_gen;

private import
	temple.temple,
	temple.util,
	temple.delims,
	std.conv,
	std.string,
	std.array,
	std.exception;

/**
 * Stack and generator for unique temporary variable names
 */
private static struct TempBufferNameStack
{
private:
	const string base;
	uint counter = 0;
	string[] stack;

public:
	this(string base)
	{
		this.base = base;
	}

	/**
	 * getNew
	 * Gets a new unique buffer variable name
	 */
	string pushNew()
	{
		auto name = base ~ counter.to!string;
		counter++;
		stack ~= name;
		return name;
	}

	/**
	 * Pops the topmost unique variable name off the stack
	 */
	string pop()
	{
		auto ret = stack[$-1];
		stack.length--;
		return ret;
	}

	/**
	 * Checks if there are any names to pop off
	 */
	bool empty()
	{
		return !stack.length;
	}
}

/**
 * __temple_gen_temple_func_string
 * Generates the function string to be mixed into a template which renders
 * a temple file.
 */
package string __temple_gen_temple_func_string(
	string temple_str, string temple_name, string filter_ident = "")
{
	// Output function string being composed
	auto function_str = "";

	// Indendation level for a line being pushed
	auto indent_level = 0;

	// Current line number in the temple_str being scanned
	size_t line_number = 0;

	void push_line(string[] stmts...)
	{
		foreach(i; 0..indent_level)
		{
			function_str ~= '\t';
		}
		foreach(stmt; stmts)
		{
			function_str ~= stmt;
		}
		function_str ~= '\n';
	}

	void push_linenum()
	{
		push_line(`#line ` ~ (line_number + 1).to!string ~ ` "` ~ temple_name ~ `"`);
	}

	void push_string_literal(string str)
	{
		if(str.length == 0)
			return;

		push_line(`__temple_buff.put("` ~ str.escapeQuotes() ~ `");`);
	}

	void indent()  { indent_level++; }
	void outdent() { indent_level--; }


	auto temp_var_names = TempBufferNameStack("__temple_capture_var_");

	// Tracks if the block that the parser has just
	// finished processing should be printed (e.g., is
	// it the block who's contents are assigned to the last tmp_buffer_var)
	bool[] printStartBlockTracker;
	void sawBlockStart(bool will_be_printed)
	{
		printStartBlockTracker ~= will_be_printed;
	}
	bool sawBlockEnd()
	{
		auto will_be_printed = printStartBlockTracker[$-1];
		printStartBlockTracker.length--;
		return will_be_printed;
	}

	string function_type_params = "";
	if(filter_ident.length)
	{
		function_type_params = "(%s)".format(filter_ident);
	}
	push_line(`static void TempleFunc%s(OutputStream __temple_buff, TempleContext __temple_context = null) {`.format(function_type_params));

	// This isn't just an overload of __templeBuffFilteredPut because D doesn't allow
	// overloading of nested functions
	push_line(q{
		void __templeBuffPutStream(AppenderOutputStream os)
		{
			__temple_buff.put(os.data);
		}

	});

	push_line(q{
		/// Calls renderWith, with the current Temple context
		AppenderOutputStream render(string __temple_file)()
		{
			return renderWith!__temple_file(__temple_context);
		}
	});

	// Is the template using a filter?
	if(filter_ident.length)
	{
		push_line(q{
			/// Run 'thing' through the Filter's templeFilter static
			void __templeBuffFilteredPut(T)(T thing)
			{
				static if(__traits(compiles, __fp__.templeFilter(cast(OutputStream) __temple_buff, thing))) {
					// The filter defines a method that takes an OutputBuffer,
					// prefer that to appending an entire string
					__fp__.templeFilter(__temple_buff, thing);
				}
				else {
					// Fall back to templeFilter returning a string
					__temple_buff.put( __fp__.templeFilter(thing) );
				}
			}

			/// Renders a subtemplate here with an explicitly defined context
			/// By default, the context is null, so a blank context will be
			/// used to render the nested template
			AppenderOutputStream renderWith(string __temple_file)(TempleContext __ctx = null)
			{
				alias __temple_render_func = TempleFile!(__temple_file, __fp__);
				return __temple_context.__templeRenderWith(&__temple_render_func, __ctx);
			}

		}.replace("__fp__", filter_ident));
	}
	else
	{
		// No filter means just directly append the thing to the
		// buffer, converting it to a string if needed
		push_line(q{
			void __templeBuffFilteredPut(T)(T thing)
			{
				__temple_buff.put(.std.conv.to!string(thing));
			}

			/// Same as the renderWith when a filter is given, just
			/// without the filter
			AppenderOutputStream renderWith(string __temple_file)(TempleContext __ctx = null)
			{
				alias __temple_render_func = TempleFile!__temple_file;
				return __temple_context.__templeRenderWith(&__temple_render_func, __ctx);
			}
		});
	}

	push_line(q{
		// Ensure that __temple_context is never null
		if(__temple_context is null)
		{
			__temple_context = new TempleContext();
		}

		// A stack of the current temple buffers, used to render nested
		// templates with
		OutputStream[] __temple_buffers;
		void __pushBuff(OutputStream __new_buff)
		{
			__temple_buffers ~= __temple_buff;
			__temple_buff = __new_buff;
		}

		void __popBuff()
		{
			__temple_buff = __temple_buffers[$-1];
			__temple_buffers.length--;
		}

		// Push this template's hooks to the current context
		__temple_context.__templePushHooks(&__pushBuff, &__popBuff);
		scope(exit) { __temple_context.__templePopHooks(); }
	});

	indent();
	if(filter_ident.length)
	{
		push_line(`with(%s)`.format(filter_ident));
	}
	push_line(`with(__temple_context) {`);
	indent();

	// Keeps infinite loops from outright crashing the compiler
	// The limit should be set to some arbitrary large number
	uint safeswitch = 0;

	string prevTempl = "";

	while(temple_str.length)
	{
		// This imposes the limiatation of a max of 10_000 delimers parsed for
		// a template function. Probably will never ever hit this in a single
		// template file without running out of compiler memory
		if(safeswitch++ > 10_000)
		{
			assert(false, "nesting level too deep; throwing saftey switch: \n" ~ temple_str);
		}

		DelimPos!(OpenDelim)* oDelimPos = temple_str.nextDelim(OpenDelims);

		if(oDelimPos is null)
		{
			//No more delims; append the rest as a string
			push_linenum();
			push_string_literal(temple_str);
			prevTempl.munchHeadOf(temple_str, temple_str.length);
		}
		else
		{
			immutable OpenDelim  oDelim = oDelimPos.delim;
			immutable CloseDelim cDelim = OpenToClose[oDelim];

			if(oDelimPos.pos == 0)
			{
				if(oDelim.isShort())
				{
					if(!prevTempl.validBeforeShort())
					{
						// Chars before % weren't all whitespace, assume it's part of a
						// string literal.
						push_linenum();
						push_string_literal(temple_str[0..oDelim.toString().length]);
						prevTempl.munchHeadOf(temple_str, oDelim.toString().length);
						continue;
					}
				}

				// If we made it this far, we've got valid open/close delims
				auto cDelimPos = temple_str.nextDelim([cDelim]);
				if(cDelimPos is null)
				{
					if(oDelim.isShort())
					{
						// don't require a short close delim at the end of the template
						temple_str ~= cDelim.toString();
						cDelimPos = enforce(temple_str.nextDelim([cDelim]));
					}
					else
					{
						assert(false, "Missing close delimer: " ~ cDelim.toString());
					}
				}

				// Made it this far, we've got the position of the close delimer.
				push_linenum();

				// Get a slice to the content between the delimers
				immutable string inbetween_delims =
					temple_str[oDelim.toString().length .. cDelimPos.pos];

				// track block starts
				immutable bool is_block_start = inbetween_delims.isBlockStart();
				immutable bool is_block_end   = inbetween_delims.isBlockEnd();

				// Invariant
				assert(!(is_block_start && is_block_end), "Internal bug: " ~ inbetween_delims);

				if(is_block_start)
				{
					sawBlockStart(oDelim.isStr());
				}

				if(oDelim.isStr())
				{
					// Check if this is a block; in that case, put the block's
					// contents into a temporary variable, then render that
					// variable after the block close delim

					// The line would look like:
					// <%= capture(() { %>
					//  <% }); %>
					// so look for something like "){" or ") {" at the end

					if(is_block_start)
					{
						string tmp_name = temp_var_names.pushNew();
						push_line(`auto %s = %s`.format(tmp_name, inbetween_delims));
						indent();
					}
					else
					{
						push_line(q{
							// AppenderOuputStream should never be passed through
							// a filter; it should be directly appended to the stream
							static if(is(typeof(__expr__) == AppenderOutputStream))
							{
								__templeBuffPutStream(__expr__);
							}

							// But other content should be filtered
							else
							{
								__templeBuffFilteredPut(__expr__);
							}
						}.replace("__expr__", inbetween_delims));

						if(cDelim == CloseDelim.CloseShort)
						{
							push_line(`__templeBuffFilteredPut("\n");`);
						}
					}
				}
				else
				{
					// It's just raw code, push it into the function body
					push_line(inbetween_delims);

					// Check if the code looks like the ending to a block;
					// e.g. for block:
					// <%= capture(() { %>
					// <% }, "foo"); %>`
					// look for it starting with }<something>);
					// If it does, output the last tmp buffer var on the stack
					if(is_block_end && !temp_var_names.empty)
					{

						// the block at this level should be printed
						if(sawBlockEnd())
						{
							outdent();
							push_line(`__temple_buff.put(%s);`.format(temp_var_names.pop()));
						}
					}
				}

				// remove up to the closing delimer
				prevTempl.munchHeadOf(
					temple_str,
					cDelimPos.pos + cDelim.toString().length);
			}
			else
			{
				// Move ahead to the next open delimer, rendering
				// everything between here and there as a string literal
				push_linenum();
				immutable delim_pos = oDelimPos.pos;
				push_string_literal(temple_str[0..delim_pos]);
				prevTempl.munchHeadOf(temple_str, delim_pos);
			}
		}

		// count the number of newlines in the previous part of the template;
		// that's the current line number
		line_number = prevTempl.count('\n');
	}

	outdent();
	push_line("}");
	outdent();
	push_line("}");

	return function_str;
}
