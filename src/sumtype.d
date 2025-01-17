/++
A sum type for modern D.

This module provides [SumType], an alternative to `std.variant.Algebraic` with
[match|improved pattern-matching], full attribute correctness (`pure`, `@safe`,
`@nogc`, and `nothrow` are inferred whenever possible), and no dependency on
runtime type information (`TypeInfo`).

License: MIT
Authors: Paul Backus, Atila Neves
+/
module sumtype;

/// $(H3 Basic usage)
@safe unittest {
    import std.math: approxEqual;

    struct Fahrenheit { double degrees; }
    struct Celsius { double degrees; }
    struct Kelvin { double degrees; }

    alias Temperature = SumType!(Fahrenheit, Celsius, Kelvin);

    // Construct from any of the member types.
    Temperature t1 = Fahrenheit(98.6);
    Temperature t2 = Celsius(100);
    Temperature t3 = Kelvin(273);

    // Use pattern matching to access the value.
    pure @safe @nogc nothrow
    Fahrenheit toFahrenheit(Temperature t)
    {
        return Fahrenheit(
            t.match!(
                (Fahrenheit f) => f.degrees,
                (Celsius c) => c.degrees * 9.0/5 + 32,
                (Kelvin k) => k.degrees * 9.0/5 - 459.4
            )
        );
    }

    assert(toFahrenheit(t1).degrees.approxEqual(98.6));
    assert(toFahrenheit(t2).degrees.approxEqual(212));
    assert(toFahrenheit(t3).degrees.approxEqual(32));

    // Use ref to modify the value in place.
    pure @safe @nogc nothrow
    void freeze(ref Temperature t)
    {
        t.match!(
            (ref Fahrenheit f) => f.degrees = 32,
            (ref Celsius c) => c.degrees = 0,
            (ref Kelvin k) => k.degrees = 273
        );
    }

    freeze(t1);
    assert(toFahrenheit(t1).degrees.approxEqual(32));

    // Use a catch-all handler to give a default result.
    pure @safe @nogc nothrow
    bool isFahrenheit(Temperature t)
    {
        return t.match!(
            (Fahrenheit f) => true,
            _ => false
        );
    }

    assert(isFahrenheit(t1));
    assert(!isFahrenheit(t2));
    assert(!isFahrenheit(t3));
}

/** $(H3 Introspection-based matching)
 *
 * In the `length` and `horiz` functions below, the handlers for `match` do not
 * specify the types of their arguments. Instead, matching is done based on how
 * the argument is used in the body of the handler: any type with `x` and `y`
 * properties will be matched by the `rect` handlers, and any type with `r` and
 * `theta` properties will be matched by the `polar` handlers.
 */
@safe unittest {
    import std.math: approxEqual, cos, PI, sqrt;

    struct Rectangular { double x, y; }
    struct Polar { double r, theta; }
    alias Vector = SumType!(Rectangular, Polar);

    pure @safe @nogc nothrow
    double length(Vector v)
    {
        return v.match!(
            rect => sqrt(rect.x^^2 + rect.y^^2),
            polar => polar.r
        );
    }

    pure @safe @nogc nothrow
    double horiz(Vector v)
    {
        return v.match!(
            rect => rect.x,
            polar => polar.r * cos(polar.theta)
        );
    }

    Vector u = Rectangular(1, 1);
    Vector v = Polar(1, PI/4);

    assert(length(u).approxEqual(sqrt(2.0)));
    assert(length(v).approxEqual(1));
    assert(horiz(u).approxEqual(1));
    assert(horiz(v).approxEqual(sqrt(0.5)));
}

/** $(H3 Arithmetic expression evaluator)
 *
 * This example makes use of the special placeholder type `This` to define a
 * [https://en.wikipedia.org/wiki/Recursive_data_type|recursive data type]: an
 * [https://en.wikipedia.org/wiki/Abstract_syntax_tree|abstract syntax tree] for
 * representing simple arithmetic expressions.
 */
@safe unittest {
    import std.functional: partial;
    import std.traits: EnumMembers;
    import std.typecons: Tuple;

    enum Op : string
    {
        Plus  = "+",
        Minus = "-",
        Times = "*",
        Div   = "/"
    }

    // An expression is either
    //  - a number,
    //  - a variable, or
    //  - a binary operation combining two sub-expressions.
    alias Expr = SumType!(
        double,
        string,
        Tuple!(Op, "op", This*, "lhs", This*, "rhs")
    );

    // Shorthand for Tuple!(Op, "op", Expr*, "lhs", Expr*, "rhs"),
    // the Tuple type above with Expr substituted for This.
    alias BinOp = Expr.Types[2];

    // Factory function for number expressions
    pure @safe
    Expr* num(double value)
    {
        return new Expr(value);
    }

    // Factory function for variable expressions
    pure @safe
    Expr* var(string name)
    {
        return new Expr(name);
    }

    // Factory function for binary operation expressions
    pure @safe
    Expr* binOp(Op op, Expr* lhs, Expr* rhs)
    {
        return new Expr(BinOp(op, lhs, rhs));
    }

    // Convenience wrappers for creating BinOp expressions
    alias sum  = partial!(binOp, Op.Plus);
    alias diff = partial!(binOp, Op.Minus);
    alias prod = partial!(binOp, Op.Times);
    alias quot = partial!(binOp, Op.Div);

    // Evaluate expr, looking up variables in env
    pure @safe nothrow
    double eval(Expr expr, double[string] env)
    {
        return expr.match!(
            (double num) => num,
            (string var) => env[var],
            (BinOp bop) {
                double lhs = eval(*bop.lhs, env);
                double rhs = eval(*bop.rhs, env);
                final switch(bop.op) {
                    static foreach(op; EnumMembers!Op) {
                        case op:
                            return mixin("lhs" ~ op ~ "rhs");
                    }
                }
            }
        );
    }

    // Return a "pretty-printed" representation of expr
    @safe
    string pprint(Expr expr)
    {
        import std.format;

        return expr.match!(
            (double num) => "%g".format(num),
            (string var) => var,
            (BinOp bop) => "(%s %s %s)".format(
                pprint(*bop.lhs),
                bop.op,
                pprint(*bop.rhs)
            )
        );
    }

    Expr* myExpr = sum(var("a"), prod(num(2), var("b")));
    double[string] myEnv = ["a":3, "b":4, "c":7];

    assert(eval(*myExpr, myEnv) == 11);
    assert(pprint(*myExpr) == "(a + (2 * b))");
}

/// `This` placeholder, for use in self-referential types.
public import std.variant: This;

import std.meta: NoDuplicates;

/**
 * A tagged union that can hold a single value from any of a specified set of
 * types.
 *
 * The value in a `SumType` can be operated on using [match|pattern matching].
 *
 * The special type `This` can be used as a placeholder to create
 * self-referential types, just like with `Algebraic`. See the
 * [sumtype#arithmetic-expression-evaluator|"Arithmetic expression evaluator" example] for
 * usage.
 *
 * A `SumType` is initialized by default to hold the `.init` value of its
 * first member type, just like a regular union. The version identifier
 * `SumTypeNoDefaultCtor` can be used to disable this behavior.
 *
 * To avoid ambiguity, duplicate types are not allowed (but see the
 * [sumtype#basic-usage|"basic usage" example] for a workaround).
 *
 * Bugs:
 *   Types with `@disable`d `opEquals` overloads cannot be members of a
 *   `SumType`.
 *
 * See_Also: `std.variant.Algebraic`
 */
struct SumType(TypeArgs...)
	if (is(NoDuplicates!TypeArgs == TypeArgs) && TypeArgs.length > 0)
{
	import std.meta: AliasSeq, Filter, anySatisfy, allSatisfy;
	import std.traits: hasElaborateCopyConstructor, hasElaborateDestructor;
	import std.traits: isAssignable, isCopyable, isStaticArray;

	/// The types a `SumType` can hold.
	alias Types = AliasSeq!(ReplaceTypeUnless!(isSumType, This, typeof(this), TypeArgs));

private:

	enum bool canHoldTag(T) = Types.length <= T.max;
	alias unsignedInts = AliasSeq!(ubyte, ushort, uint, ulong);

	alias Tag = Filter!(canHoldTag, unsignedInts)[0];

	union Storage
	{
		Types values;

		static foreach (i, T; Types) {
			@trusted
			this()(scope auto ref T val)
			{
				import std.functional: forward;

				static if (isCopyable!T) {
					values[i] = val;
				} else {
					values[i] = forward!val;
				}
			}

			static if (isCopyable!T) {
				@trusted
				this()(auto ref const(T) val) const
				{
					values[i] = val;
				}

				@trusted
				this()(auto ref immutable(T) val) immutable
				{
					values[i] = val;
				}
			} else {
				@disable this(const(T) val) const;
				@disable this(immutable(T) val) immutable;
			}
		}
	}

	Tag tag;
	Storage storage;

	@trusted
	ref inout(T) trustedGet(T)() inout
	{
		import std.meta: staticIndexOf;

		enum tid = staticIndexOf!(T, Types);
		assert(tag == tid);
		return storage.values[tid];
	}

public:

	static foreach (i, T; Types) {
		/// Constructs a `SumType` holding a specific value.
		this()(auto ref T val)
		{
			import std.functional: forward;

			static if (isCopyable!T) {
				storage = Storage(val);
			} else {
				storage = Storage(forward!val);
			}

			tag = i;
		}

		static if (isCopyable!T) {
			/// ditto
			this()(auto ref const(T) val) const
			{
				storage = const(Storage)(val);
				tag = i;
			}

			/// ditto
			this()(auto ref immutable(T) val) immutable
			{
				storage = immutable(Storage)(val);
				tag = i;
			}
		} else {
			@disable this(const(T) val) const;
			@disable this(immutable(T) val) immutable;
		}
	}

	version(SumTypeNoDefaultCtor) {
		@disable this();
	}

	static foreach (i, T; Types) {
		static if (isAssignable!T) {
			/// Assigns a value to a `SumType`.
			void opAssign()(auto ref T rhs)
			{
				import std.functional: forward;

				this.match!((ref value) {
					static if (hasElaborateDestructor!(typeof(value))) {
						destroy(value);
					}
				});

				storage = Storage(forward!rhs);
				tag = i;
			}
		}
	}

	/**
	 * Compares two `SumType`s for equality.
	 *
	 * Two `SumType`s are equal if they are the same kind of `SumType`, they
	 * contain values of the same type, and those values are equal.
	 */
	bool opEquals(const SumType rhs) const {
		return this.match!((ref value) {
			return rhs.match!((ref rhsValue) {
				static if (is(typeof(value) == typeof(rhsValue))) {
					return value == rhsValue;
				} else {
					return false;
				}
			});
		});
	}

	// Workaround for dlang issue 19407
	static if (__traits(compiles, anySatisfy!(hasElaborateDestructor, Types))) {
		// If possible, include the destructor only when it's needed
		private enum includeDtor = anySatisfy!(hasElaborateDestructor, Types);
	} else {
		// If we can't tell, always include it, even when it does nothing
		private enum includeDtor = true;
	}

	static if (includeDtor) {
		/// Calls the destructor of the `SumType`'s current value.
		~this()
		{
			this.match!((ref value) {
				static if (hasElaborateDestructor!(typeof(value))) {
					destroy(value);
				}
			});
		}
	}

	static if (allSatisfy!(isCopyable, Types)) {
		static if (anySatisfy!(hasElaborateCopyConstructor, Types)) {
			/// Calls the postblit of the `SumType`'s current value.
			this(this)
			{
				static void callPostblits(T)(ref T value)
					if (hasElaborateCopyConstructor!T)
				{
					static if (isStaticArray!T) {
						foreach (ref element; value) {
							callPostblits(element);
						}
					} else {
						value.__xpostblit;
					}
				}

				this.match!((ref value) {
					static if (hasElaborateCopyConstructor!(typeof(value))) {
						callPostblits(value);
					}
				});
			}
		}
	} else {
		@disable this(this);
	}

	static if (allSatisfy!(isCopyable, Types)) {
		/// Returns a string representation of a `SumType`'s value.
		string toString(this T)() {
			import std.conv: text;
			return this.match!((auto ref value) {
				return value.text;
			});
		}
	}
}

/**
 * Returns `true` if and if `T` is an instance of `SumType`.
 *
 * Params:
 *     T = The type to check.
 *
 * Returns:
 *     true if `T` is a `SumType` type, false otherwise.
 */
enum isSumType(T) = is(T == SumType!Args, Args...);

// Construction
@safe unittest {
	alias MySum = SumType!(int, float);

	assert(__traits(compiles, MySum(42)));
	assert(__traits(compiles, MySum(3.14)));
}

// Assignment
@safe unittest {
	alias MySum = SumType!(int, float);

	MySum x = MySum(42);

	assert(__traits(compiles, x = 3.14));
}

// Self assignment
@safe unittest {
	alias MySum = SumType!(int, float);

	MySum x = MySum(42);
	MySum y = MySum(3.14);

	assert(__traits(compiles, y = x));
}

// Equality
@safe unittest {
	alias MySum = SumType!(int, float);

	MySum x = MySum(123);
	MySum y = MySum(123);
	MySum z = MySum(456);
	MySum w = MySum(123.0);
	MySum v = MySum(456.0);

	assert(x == y);
	assert(x != z);
	assert(x != w);
	assert(x != v);
}

// Imported types
@safe unittest {
	import std.typecons: Tuple;

	assert(__traits(compiles, {
		alias MySum = SumType!(Tuple!(int, int));
	}));
}

// const and immutable types
@safe unittest {
	assert(__traits(compiles, {
		alias MySum = SumType!(const(int[]), immutable(float[]));
	}));
}

// Recursive types
@safe unittest {
	alias MySum = SumType!(This*);
	assert(is(MySum.Types[0] == MySum*));
}

// Allowed types
@safe unittest {
	import std.meta: AliasSeq;

	alias MySum = SumType!(int, float, This*);

	assert(is(MySum.Types == AliasSeq!(int, float, MySum*)));
}

// Works alongside Algebraic
@safe unittest {
	import std.variant;

	alias Bar = Algebraic!(This*);

	assert(is(Bar.AllowedTypes[0] == Bar*));
}

// Types with destructors and postblits
@safe unittest {
	int copies;

	struct Test
	{
		bool initialized = false;

		this(this) { copies++; }
		~this() { if (initialized) copies--; }
	}

	alias MySum = SumType!(int, Test);

	Test t = Test(true);

	{
		MySum x = t;
		assert(copies == 1);
	}
	assert(copies == 0);

	{
		MySum x = 456;
		assert(copies == 0);
	}
	assert(copies == 0);

	{
		MySum x = t;
		assert(copies == 1);
		x = 456;
		assert(copies == 0);
	}

	{
		MySum x = 456;
		assert(copies == 0);
		x = t;
		assert(copies == 1);
	}
}

// Doesn't destroy reference types
@safe unittest {
	bool destroyed;

	class C
	{
		~this()
		{
			destroyed = true;
		}
	}

	struct S
	{
		~this() {}
	}

	alias MySum = SumType!(S, C);

	C c = new C();
	{
		MySum x = c;
		destroyed = false;
	}
	assert(!destroyed);

	{
		MySum x = c;
		destroyed = false;
		x = S();
		assert(!destroyed);
	}
}

// Types with @disable this()
@safe unittest {
	struct NoInit
	{
		@disable this();
	}

	alias MySum = SumType!(NoInit, int);

	assert(!__traits(compiles, MySum()));
	assert(__traits(compiles, MySum(42)));
}

// const SumTypes
@safe unittest {
	assert(__traits(compiles,
		const(SumType!(int[]))([1, 2, 3])
	));
}

// Equality of const SumTypes
@safe unittest {
	alias MySum = SumType!int;

	assert(__traits(compiles,
		const(MySum)(123) == const(MySum)(456)
	));
}

// Compares reference types using value equality
@safe unittest {
	struct Field {}
	struct Struct { Field[] fields; }
	alias MySum = SumType!Struct;

	auto a = MySum(Struct([Field()]));
	auto b = MySum(Struct([Field()]));

	assert(a == b);
}

// toString
@safe unittest {
	import std.conv: text;

	static struct Int { int i; }
	static struct Double { double d; }
	alias Sum = SumType!(Int, Double);

	assert(Sum(Int(42)).text == Int(42).text, Sum(Int(42)).text);
	assert(Sum(Double(33.3)).text == Double(33.3).text, Sum(Double(33.3)).text);
	assert((const(Sum)(Int(42))).text == (const(Int)(42)).text, (const(Sum)(Int(42))).text);
}

// Github issue #16
@safe unittest {
	alias Node = SumType!(This[], string);

	// override inference of @system attribute for cyclic functions
	assert((() @trusted =>
		Node([Node([Node("x")])])
		==
		Node([Node([Node("x")])])
	)());
}

// Github issue #16 with const
@safe unittest {
	alias Node = SumType!(const(This)[], string);

	// override inference of @system attribute for cyclic functions
	assert((() @trusted =>
		Node([Node([Node("x")])])
		==
		Node([Node([Node("x")])])
	)());
}

// Stale pointers
@system unittest {
	import std.array: staticArray;

	alias MySum = SumType!(ubyte, void*[2]);

	MySum x = [null, cast(void*) 0x12345678];
	void** p = &x.trustedGet!(void*[2])[1];
	x = ubyte(123);

	assert(*p != cast(void*) 0x12345678);
}

// Exception-safe assignment
@safe unittest {
	struct A
	{
		int value = 123;
	}

	struct B
	{
		int value = 456;
		this(this) { throw new Exception("oops"); }
	}

	alias MySum = SumType!(A, B);

	MySum x;
	try {
		x = B();
	} catch (Exception e) {}

	assert(
		(x.tag == 0 && x.trustedGet!A.value == 123) ||
		(x.tag == 1 && x.trustedGet!B.value == 456)
	);
}

// Types with @disable this(this)
@safe unittest {
	import std.algorithm.mutation: move;

	struct NoCopy
	{
		@disable this(this);
	}

	alias MySum = SumType!NoCopy;

	NoCopy lval = NoCopy();

	MySum x = NoCopy();
	MySum y = NoCopy();

	assert(__traits(compiles, SumType!NoCopy(NoCopy())));
	assert(!__traits(compiles, SumType!NoCopy(lval)));

	assert(__traits(compiles, y = NoCopy()));
	assert(__traits(compiles, y = move(x)));
	assert(!__traits(compiles, y = lval));
	assert(!__traits(compiles, y = x));
}

// Github issue #22
@safe unittest {
	import std.typecons;
	assert(__traits(compiles, {
		static struct A {
			SumType!(Nullable!int) a = Nullable!int.init;
		}
	}));
}

// Static arrays of structs with postblits
@safe unittest {
	struct S
	{
		int n;
		this(this) { n++; }
	}

	assert(__traits(compiles, SumType!(S[1])()));

	SumType!(S[1]) x = [S(0)];
	SumType!(S[1]) y = x;

	auto xval = x.storage.values[0][0].n;
	auto yval = y.storage.values[0][0].n;

	assert(xval != yval);
}

version(none) {
	// Known bug; needs fix for dlang issue 19458
	// Types with disabled opEquals
	@safe unittest {
		struct S
		{
			@disable bool opEquals(const S rhs) const;
		}

		assert(__traits(compiles, SumType!S(S())));
	}
}

version(none) {
	// Known bug; needs fix for dlang issue 19458
	@safe unittest {
		struct S
		{
			int i;
			bool opEquals(S rhs) { return i == rhs.i; }
		}

		assert(__traits(compiles, SumType!S(S(123))));
	}
}

/**
 * Calls a type-appropriate function with the value held in a [SumType].
 *
 * For each possible type the [SumType] can hold, the given handlers are
 * checked, in order, to see whether they accept a single argument of that type.
 * The first one that does is chosen as the match for that type.
 *
 * Implicit conversions are not taken into account, except between
 * differently-qualified versions of the same type. For example, a handler that
 * accepts a `long` will not match the type `int`, but a handler that accepts a
 * `const(int)[]` will match the type `immutable(int)[]`.
 *
 * Every type must have a matching handler, and every handler must match at
 * least one type. This is enforced at compile time.
 *
 * Handlers may be functions, delegates, or objects with opCall overloads. If a
 * function with more than one overload is given as a handler, all of the
 * overloads are considered as potential matches.
 *
 * Templated handlers are also accepted, and will match any type for which they
 * can be [implicitly instantiated](https://dlang.org/glossary.html#ifti). See
 * [sumtype#introspection-based-matching|"Introspection-based matching"] for an
 * example of templated handler usage.
 *
 * Returns:
 *   The value returned from the handler that matches the currently-held type.
 *
 * See_Also: `std.variant.visit`
 */
template match(handlers...)
{
	import std.typecons: Yes;

	/**
	 * The actual `match` function.
	 *
	 * Params:
	 *   self = A [SumType] object
	 */
	auto match(Self)(auto ref Self self)
		if (is(Self : SumType!TypeArgs, TypeArgs...))
	{
		return self.matchImpl!(Yes.exhaustive, handlers);
	}
}

/**
 * Attempts to call a type-appropriate function with the value held in a
 * [SumType], and throws on failure.
 *
 * Matches are chosen using the same rules as [match], but are not required to
 * be exhaustive—in other words, a type is allowed to have no matching handler.
 * If a type without a handler is encountered at runtime, a [MatchException]
 * is thrown.
 *
 * Returns:
 *   The value returned from the handler that matches the currently-held type,
 *   if a handler was given for that type.
 *
 * Throws:
 *   [MatchException], if the currently-held type has no matching handler.
 *
 * See_Also: `std.variant.tryVisit`
 */
template tryMatch(handlers...)
{
	import std.typecons: No;

	/**
	 * The actual `tryMatch` function.
	 *
	 * Params:
	 *   self = A [SumType] object
	 */
	auto tryMatch(Self)(auto ref Self self)
		if (is(Self : SumType!TypeArgs, TypeArgs...))
	{
		return self.matchImpl!(No.exhaustive, handlers);
	}
}

/// Thrown by [tryMatch] when an unhandled type is encountered.
class MatchException : Exception
{
	pure @safe @nogc nothrow
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

/**
 * Checks whether a handler can match a given type.
 *
 * See the documentation for [match] for a full explanation of how matches are
 * chosen.
 */
template canMatch(alias handler, T)
{
	private bool canMatchImpl()
	{
		import std.traits: hasMember, isCallable, isSomeFunction, Parameters;

		// Include overloads even when called from outside of matchImpl
		alias realHandler = handlerWithOverloads!handler;

		// immutable recursively overrides all other qualifiers, so the
		// right-hand side is true if and only if the two types are the
		// same when qualifiers are ignored.
		enum sameUpToQuals(T, U) = is(immutable(T) == immutable(U));

		bool result = false;

		static if (is(typeof((T arg) { realHandler(arg); }(T.init)))) {
			// Regular handlers
			static if (isCallable!realHandler) {
				// Functions and delegates
				static if (isSomeFunction!realHandler) {
					static if (sameUpToQuals!(T, Parameters!realHandler[0])) {
						result = true;
					}
				// Objects with overloaded opCall
				} else static if (hasMember!(typeof(realHandler), "opCall")) {
					static foreach (overload; __traits(getOverloads, typeof(realHandler), "opCall")) {
						static if (sameUpToQuals!(T, Parameters!overload[0])) {
							result = true;
						}
					}
				}
			// Generic handlers
			} else {
				result = true;
			}
		}

		return result;
	}

	/// True if `handler` is a potential match for `T`, otherwise false.
	enum bool canMatch = canMatchImpl;
}

// Includes all overloads of the given handler
@safe unittest {
	static struct OverloadSet
	{
		static void fun(int n) {}
		static void fun(double d) {}
	}

	assert(canMatch!(OverloadSet.fun, int));
	assert(canMatch!(OverloadSet.fun, double));
}

import std.traits: isFunction;

// An AliasSeq of a function's overloads
private template FunctionOverloads(alias fun)
	if (isFunction!fun)
{
	import std.meta: AliasSeq;

	alias FunctionOverloads = AliasSeq!(
		__traits(getOverloads,
			__traits(parent, fun),
			__traits(identifier, fun)
		)
	);
}

// A struct with an opCall overload for each overload of fun
private struct OverloadDispatcher(alias fun)
	if (isFunction!fun)
{
	import std.traits: Parameters, ReturnType;

	pragma(inline, true):

	static foreach(overload; FunctionOverloads!fun) {
		ReturnType!overload opCall(Parameters!overload args)
		{
			return overload(args);
		}
	}
}

// A handler that includes all overloads of the original handler, if applicable
private template handlerWithOverloads(alias handler)
{
	// Delegates and function pointers can't have overloads
	static if (isFunction!handler && FunctionOverloads!handler.length > 1) {
		enum handlerWithOverloads = OverloadDispatcher!handler.init;
	} else {
		alias handlerWithOverloads = handler;
	}
}

import std.typecons: Flag;

private template matchImpl(Flag!"exhaustive" exhaustive, handlers...)
{
	auto matchImpl(Self)(auto ref Self self)
		if (is(Self : SumType!TypeArgs, TypeArgs...))
	{
		import std.meta: staticMap;

		alias Types = self.Types;
		enum noMatch = size_t.max;

		alias allHandlers = staticMap!(handlerWithOverloads, handlers);

		pure size_t[Types.length] getHandlerIndices()
		{
			size_t[Types.length] indices;
			indices[] = noMatch;

			static foreach (tid, T; Types) {
				static foreach (hid, handler; allHandlers) {
					static if (canMatch!(handler, typeof(self.trustedGet!T()))) {
						if (indices[tid] == noMatch) {
							indices[tid] = hid;
						}
					}
				}
			}

			return indices;
		}

		enum handlerIndices = getHandlerIndices;

		import std.algorithm.searching: canFind;

		// Check for unreachable handlers
		static foreach (hid, handler; allHandlers) {
			static assert(handlerIndices[].canFind(hid),
				"handler `" ~ __traits(identifier, handler) ~ "` " ~
				"of type `" ~ typeof(handler).stringof ~ "` " ~
				"never matches"
			);
		}

		final switch (self.tag) {
			static foreach (tid, T; Types) {
				case tid:
					static if (handlerIndices[tid] != noMatch) {
						return allHandlers[handlerIndices[tid]](self.trustedGet!T);
					} else {
						static if(exhaustive) {
							static assert(false,
								"No matching handler for type `" ~ T.stringof ~ "`");
						} else {
							throw new MatchException(
								"No matching handler for type `" ~ T.stringof ~ "`");
						}
					}
			}
		}

		assert(false); // unreached
	}
}

// Matching
@safe unittest {
	alias MySum = SumType!(int, float);

	MySum x = MySum(42);
	MySum y = MySum(3.14);

	assert(x.match!((int v) => true, (float v) => false));
	assert(y.match!((int v) => false, (float v) => true));
}

// Missing handlers
@safe unittest {
	alias MySum = SumType!(int, float);

	MySum x = MySum(42);

	assert(!__traits(compiles, x.match!((int x) => true)));
	assert(!__traits(compiles, x.match!()));
}

// No implicit converstion
@safe unittest {
	alias MySum = SumType!(int, float);

	MySum x = MySum(42);

	assert(!__traits(compiles,
		x.match!((long v) => true, (float v) => false)
	));
}

// Handlers with qualified parameters
@safe unittest {
    alias MySum = SumType!(int[], float[]);

    MySum x = MySum([1, 2, 3]);
    MySum y = MySum([1.0, 2.0, 3.0]);

    assert(x.match!((const(int[]) v) => true, (const(float[]) v) => false));
    assert(y.match!((const(int[]) v) => false, (const(float[]) v) => true));
}

// Handlers for qualified types
@safe unittest {
	alias MySum = SumType!(immutable(int[]), immutable(float[]));

	MySum x = MySum([1, 2, 3]);

	assert(x.match!((immutable(int[]) v) => true, (immutable(float[]) v) => false));
	assert(x.match!((const(int[]) v) => true, (const(float[]) v) => false));
	// Tail-qualified parameters
	assert(x.match!((immutable(int)[] v) => true, (immutable(float)[] v) => false));
	assert(x.match!((const(int)[] v) => true, (const(float)[] v) => false));
	// Generic parameters
	assert(x.match!((immutable v) => true));
	assert(x.match!((const v) => true));
	// Unqualified parameters
	assert(!__traits(compiles,
		x.match!((int[] v) => true, (float[] v) => false)
	));
}

// Delegate handlers
@safe unittest {
	alias MySum = SumType!(int, float);

	int answer = 42;
	MySum x = MySum(42);
	MySum y = MySum(3.14);

	assert(x.match!((int v) => v == answer, (float v) => v == answer));
	assert(!y.match!((int v) => v == answer, (float v) => v == answer));
}

// Generic handler
@safe unittest {
	import std.math: approxEqual;

	alias MySum = SumType!(int, float);

	MySum x = MySum(42);
	MySum y = MySum(3.14);

	assert(x.match!(v => v*2) == 84);
	assert(y.match!(v => v*2).approxEqual(6.28));
}

// Fallback to generic handler
@safe unittest {
	import std.conv: to;

	alias MySum = SumType!(int, float, string);

	MySum x = MySum(42);
	MySum y = MySum("42");

	assert(x.match!((string v) => v.to!int, v => v*2) == 84);
	assert(y.match!((string v) => v.to!int, v => v*2) == 42);
}

// Multiple non-overlapping generic handlers
@safe unittest {
	import std.math: approxEqual;

	alias MySum = SumType!(int, float, int[], char[]);

	MySum x = MySum(42);
	MySum y = MySum(3.14);
	MySum z = MySum([1, 2, 3]);
	MySum w = MySum(['a', 'b', 'c']);

	assert(x.match!(v => v*2, v => v.length) == 84);
	assert(y.match!(v => v*2, v => v.length).approxEqual(6.28));
	assert(w.match!(v => v*2, v => v.length) == 3);
	assert(z.match!(v => v*2, v => v.length) == 3);
}

// Structural matching
@safe unittest {
	struct S1 { int x; }
	struct S2 { int y; }
	alias MySum = SumType!(S1, S2);

	MySum a = MySum(S1(0));
	MySum b = MySum(S2(0));

	assert(a.match!(s1 => s1.x + 1, s2 => s2.y - 1) == 1);
	assert(b.match!(s1 => s1.x + 1, s2 => s2.y - 1) == -1);
}

// Separate opCall handlers
@safe unittest {
	struct IntHandler
	{
		bool opCall(int arg)
		{
			return true;
		}
	}

	struct FloatHandler
	{
		bool opCall(float arg)
		{
			return false;
		}
	}

	alias MySum = SumType!(int, float);

	MySum x = MySum(42);
	MySum y = MySum(3.14);
	IntHandler handleInt;
	FloatHandler handleFloat;

	assert(x.match!(handleInt, handleFloat));
	assert(!y.match!(handleInt, handleFloat));
}

// Compound opCall handler
@safe unittest {
	struct CompoundHandler
	{
		bool opCall(int arg)
		{
			return true;
		}

		bool opCall(float arg)
		{
			return false;
		}
	}

	alias MySum = SumType!(int, float);

	MySum x = MySum(42);
	MySum y = MySum(3.14);
	CompoundHandler handleBoth;

	assert(x.match!handleBoth);
	assert(!y.match!handleBoth);
}

// Ordered matching
@safe unittest {
	alias MySum = SumType!(int, float);

	MySum x = MySum(42);

	assert(x.match!((int v) => true, v => false));
}

// Non-exhaustive matching
@system unittest {
	import std.exception: assertThrown, assertNotThrown;

	alias MySum = SumType!(int, float);

	MySum x = MySum(42);
	MySum y = MySum(3.14);

	assertNotThrown!MatchException(x.tryMatch!((int n) => true));
	assertThrown!MatchException(y.tryMatch!((int n) => true));
}

// Non-exhaustive matching in @safe code
@safe unittest {
	SumType!(int, float) x;

	assert(__traits(compiles,
		x.tryMatch!(
			(int n) => n + 1,
		)
	));

}

// Handlers with ref parameters
@safe unittest {
	import std.math: approxEqual;
	import std.meta: staticIndexOf;

	alias Value = SumType!(long, double);

	auto value = Value(3.14);

	value.match!(
		(long) {},
		(ref double d) { d *= 2; }
	);

	assert(value.trustedGet!double.approxEqual(6.28));
}

// Unreachable handlers
@safe unittest {
	alias MySum = SumType!(int, string);

	MySum s;

	assert(!__traits(compiles,
		s.match!(
			(int _) => 0,
			(string _) => 1,
			(double _) => 2
		)
	));

	assert(!__traits(compiles,
		s.match!(
			_ => 0,
			(int _) => 1
		)
	));
}

// Unsafe handlers
unittest {
	SumType!int x;
	alias unsafeHandler = (int x) @system { return; };

	assert(!__traits(compiles, () @safe {
		x.match!unsafeHandler;
	}));

	assert(__traits(compiles, () @system {
		return x.match!unsafeHandler;
	}));
}

// Overloaded handlers
@safe unittest {
	static struct OverloadSet
	{
		static string fun(int i) { return "int"; }
		static string fun(double d) { return "double"; }
	}

	alias MySum = SumType!(int, double);

	MySum a = 42;
	MySum b = 3.14;

	assert(a.match!(OverloadSet.fun) == "int");
	assert(b.match!(OverloadSet.fun) == "double");
}

// Overload sets that include SumType arguments
@safe unittest {
	alias Inner = SumType!(int, double);
	alias Outer = SumType!(Inner, string);

	static struct OverloadSet
	{
		@safe:
		static string fun(int i) { return "int"; }
		static string fun(double d) { return "double"; }
		static string fun(string s) { return "string"; }
		static string fun(Inner i) { return i.match!fun; }
		static string fun(Outer o) { return o.match!fun; }
	}

	Outer a = Inner(42);
	Outer b = Inner(3.14);
	Outer c = "foo";

	assert(OverloadSet.fun(a) == "int");
	assert(OverloadSet.fun(b) == "double");
	assert(OverloadSet.fun(c) == "string");
}

/**
 * Replaces all occurrences of `From` into `To`, in one or more types `T`
 * whenever the predicate applied to `T` evaluates to false. For example, $(D
 * ReplaceTypeUnless!(isBoolean, int, uint, Tuple!(int, float)[string])) yields
 * $(D Tuple!(uint, float)[string]) while $(D ReplaceTypeUnless!(isTuple, int,
 * string, Tuple!(int, bool)[int])) yields $(D Tuple!(int, bool)[string]). The
 * types in which replacement is performed may be arbitrarily complex,
 * including qualifiers, built-in type constructors (pointers, arrays,
 * associative arrays, functions, and delegates), and template instantiations;
 * replacement proceeds transitively through the type definition.  However,
 * member types in `struct`s or `class`es are not replaced because there are no
 * ways to express the types resulting after replacement.
 *
 * This is an advanced type manipulation necessary e.g. for replacing the
 * placeholder type `This` in $(REF SumType).
 *
 * This template is a generalised version of the one in
 * https://github.com/dlang/phobos/blob/d1c8fb0b69dc12669554d5cb96d3045753549619/std/typecons.d
 *
 * Returns: `ReplaceTypeUnless` aliases itself to the type(s) that result after
 * replacement.
*/
private template ReplaceTypeUnless(alias Pred, From, To, T...)
{
	import std.meta;

	static if (T.length == 1)
	{
		static if (Pred!(T[0]))
			alias ReplaceTypeUnless = T[0];
		else static if (is(T[0] == From))
			alias ReplaceTypeUnless = To;
		else static if (is(T[0] == const(U), U))
			alias ReplaceTypeUnless = const(ReplaceTypeUnless!(Pred, From, To, U));
		else static if (is(T[0] == immutable(U), U))
			alias ReplaceTypeUnless = immutable(ReplaceTypeUnless!(Pred, From, To, U));
		else static if (is(T[0] == shared(U), U))
			alias ReplaceTypeUnless = shared(ReplaceTypeUnless!(Pred, From, To, U));
		else static if (is(T[0] == U*, U))
		{
			static if (is(U == function))
				alias ReplaceTypeUnless = replaceTypeInFunctionTypeUnless!(Pred, From, To, T[0]);
			else
				alias ReplaceTypeUnless = ReplaceTypeUnless!(Pred, From, To, U)*;
		}
		else static if (is(T[0] == delegate))
		{
			alias ReplaceTypeUnless = replaceTypeInFunctionTypeUnless!(Pred, From, To, T[0]);
		}
		else static if (is(T[0] == function))
		{
			static assert(0, "Function types not supported," ~
				" use a function pointer type instead of " ~ T[0].stringof);
		}
		else static if (is(T[0] : U!V, alias U, V...))
		{
			template replaceTemplateArgs(T...)
			{
				static if (is(typeof(T[0])))	// template argument is value or symbol
					enum replaceTemplateArgs = T[0];
				else
					alias replaceTemplateArgs = ReplaceTypeUnless!(Pred, From, To, T[0]);
			}
			alias ReplaceTypeUnless = U!(staticMap!(replaceTemplateArgs, V));
		}
		else static if (is(T[0] == struct))
			// don't match with alias this struct below (Issue 15168)
			alias ReplaceTypeUnless = T[0];
		else static if (is(T[0] == U[], U))
			alias ReplaceTypeUnless = ReplaceTypeUnless!(Pred, From, To, U)[];
		else static if (is(T[0] == U[n], U, size_t n))
			alias ReplaceTypeUnless = ReplaceTypeUnless!(Pred, From, To, U)[n];
		else static if (is(T[0] == U[V], U, V))
			alias ReplaceTypeUnless =
				ReplaceTypeUnless!(Pred, From, To, U)[ReplaceTypeUnless!(Pred, From, To, V)];
		else
			alias ReplaceTypeUnless = T[0];
	}
	else static if (T.length > 1)
	{
		alias ReplaceTypeUnless = AliasSeq!(ReplaceTypeUnless!(Pred, From, To, T[0]),
			ReplaceTypeUnless!(Pred, From, To, T[1 .. $]));
	}
	else
	{
		alias ReplaceTypeUnless = AliasSeq!();
	}
}


private template replaceTypeInFunctionTypeUnless(alias Pred, From, To, fun)
{
	import std.traits;
	import std.meta: AliasSeq;

	alias RX = ReplaceTypeUnless!(Pred, From, To, ReturnType!fun);
	alias PX = AliasSeq!(ReplaceTypeUnless!(Pred, From, To, Parameters!fun));
	// Wrapping with AliasSeq is neccesary because ReplaceType doesn't return
	// tuple if Parameters!fun.length == 1

	string gen()
	{
		enum  linkage = functionLinkage!fun;
		alias attributes = functionAttributes!fun;
		enum  variadicStyle = variadicFunctionStyle!fun;
		alias storageClasses = ParameterStorageClassTuple!fun;

		string result;

		result ~= "extern(" ~ linkage ~ ") ";
		static if (attributes & FunctionAttribute.ref_)
		{
			result ~= "ref ";
		}

		result ~= "RX";
		static if (is(fun == delegate))
			result ~= " delegate";
		else
			result ~= " function";

		result ~= "(";
		static foreach (i; 0 .. PX.length)
		{
			if (i)
				result ~= ", ";
			if (storageClasses[i] & ParameterStorageClass.scope_)
				result ~= "scope ";
			if (storageClasses[i] & ParameterStorageClass.out_)
				result ~= "out ";
			if (storageClasses[i] & ParameterStorageClass.ref_)
				result ~= "ref ";
			if (storageClasses[i] & ParameterStorageClass.lazy_)
				result ~= "lazy ";
			if (storageClasses[i] & ParameterStorageClass.return_)
				result ~= "return ";

			result ~= "PX[" ~ i.stringof ~ "]";
		}
		static if (variadicStyle == Variadic.typesafe)
			result ~= " ...";
		else static if (variadicStyle != Variadic.no)
			result ~= ", ...";
		result ~= ")";

		static if (attributes & FunctionAttribute.pure_)
			result ~= " pure";
		static if (attributes & FunctionAttribute.nothrow_)
			result ~= " nothrow";
		static if (attributes & FunctionAttribute.property)
			result ~= " @property";
		static if (attributes & FunctionAttribute.trusted)
			result ~= " @trusted";
		static if (attributes & FunctionAttribute.safe)
			result ~= " @safe";
		static if (attributes & FunctionAttribute.nogc)
			result ~= " @nogc";
		static if (attributes & FunctionAttribute.system)
			result ~= " @system";
		static if (attributes & FunctionAttribute.const_)
			result ~= " const";
		static if (attributes & FunctionAttribute.immutable_)
			result ~= " immutable";
		static if (attributes & FunctionAttribute.inout_)
			result ~= " inout";
		static if (attributes & FunctionAttribute.shared_)
			result ~= " shared";
		static if (attributes & FunctionAttribute.return_)
			result ~= " return";

		return result;
	}

	mixin("alias replaceTypeInFunctionTypeUnless = " ~ gen() ~ ";");
}

// Adapted from:
// https://github.com/dlang/phobos/blob/d1c8fb0b69dc12669554d5cb96d3045753549619/std/typecons.d
@safe unittest {
	import std.typecons: Tuple;
	enum False(T) = false;
	static assert(
		is(ReplaceTypeUnless!(False, int, string, int[]) == string[]) &&
		is(ReplaceTypeUnless!(False, int, string, int[int]) == string[string]) &&
		is(ReplaceTypeUnless!(False, int, string, const(int)[]) == const(string)[]) &&
		is(ReplaceTypeUnless!(False, int, string, Tuple!(int[], float))
			== Tuple!(string[], float))
	);
}

// Adapted from:
// https://github.com/dlang/phobos/blob/d1c8fb0b69dc12669554d5cb96d3045753549619/std/typecons.d
@safe unittest
{
	import std.typecons;

	enum False(T) = false;
	template Test(Ts...)
	{
		static if (Ts.length)
		{
			static assert(is(ReplaceTypeUnless!(False, Ts[0], Ts[1], Ts[2]) == Ts[3]),
				"ReplaceTypeUnless!(False, "~Ts[0].stringof~", "~Ts[1].stringof~", "
					~Ts[2].stringof~") == "
					~ReplaceTypeUnless!(False, Ts[0], Ts[1], Ts[2]).stringof);
			alias Test = Test!(Ts[4 .. $]);
		}
		else alias Test = void;
	}

	import core.stdc.stdio;
	alias RefFun1 = ref int function(float, long);
	alias RefFun2 = ref float function(float, long);
	extern(C) int printf(const char*, ...) nothrow @nogc @system;
	extern(C) float floatPrintf(const char*, ...) nothrow @nogc @system;
	int func(float);

	int x;
	struct S1 { void foo() { x = 1; } }
	struct S2 { void bar() { x = 2; } }

	alias Pass = Test!(
		int, float, typeof(&func), float delegate(float),
		int, float, typeof(&printf), typeof(&floatPrintf),
		int, float, int function(out long, ...),
			float function(out long, ...),
		int, float, int function(ref float, long),
			float function(ref float, long),
		int, float, int function(ref int, long),
			float function(ref float, long),
		int, float, int function(out int, long),
			float function(out float, long),
		int, float, int function(lazy int, long),
			float function(lazy float, long),
		int, float, int function(out long, ref const int),
			float function(out long, ref const float),
		int, int, int, int,
		int, float, int, float,
		int, float, const int, const float,
		int, float, immutable int, immutable float,
		int, float, shared int, shared float,
		int, float, int*, float*,
		int, float, const(int)*, const(float)*,
		int, float, const(int*), const(float*),
		const(int)*, float, const(int*), const(float),
		int*, float, const(int)*, const(int)*,
		int, float, int[], float[],
		int, float, int[42], float[42],
		int, float, const(int)[42], const(float)[42],
		int, float, const(int[42]), const(float[42]),
		int, float, int[int], float[float],
		int, float, int[double], float[double],
		int, float, double[int], double[float],
		int, float, int function(float, long), float function(float, long),
		int, float, int function(float), float function(float),
		int, float, int function(float, int), float function(float, float),
		int, float, int delegate(float, long), float delegate(float, long),
		int, float, int delegate(float), float delegate(float),
		int, float, int delegate(float, int), float delegate(float, float),
		int, float, Unique!int, Unique!float,
		int, float, Tuple!(float, int), Tuple!(float, float),
		int, float, RefFun1, RefFun2,
		S1, S2,
			S1[1][][S1]* function(),
			S2[1][][S2]* function(),
		int, string,
			   int[3] function(   int[] arr,	int[2] ...) pure @trusted,
			string[3] function(string[] arr, string[2] ...) pure @trusted,
	);

	// Dlang Bugzilla 15168
	static struct T1 { string s; alias s this; }
	static struct T2 { char[10] s; alias s this; }
	static struct T3 { string[string] s; alias s this; }
	alias Pass2 = Test!(
		ubyte, ubyte, T1, T1,
		ubyte, ubyte, T2, T2,
		ubyte, ubyte, T3, T3,
	);
}

@safe unittest // Dlang Bugzilla 17116
{
	enum False(T) = false;
	alias ConstDg = void delegate(float) const;
	alias B = void delegate(int) const;
	alias A = ReplaceTypeUnless!(False, float, int, ConstDg);
	static assert(is(B == A));
}


// Replacement does not happen inside SumType
@safe unittest {
	import std.typecons : Tuple;
	alias A = Tuple!(This*,SumType!(This*))[SumType!(This*,string)[This]];
	alias TR = ReplaceTypeUnless!(isSumType, This, int, A);
	static assert(is(TR == Tuple!(int*,SumType!(This*))[SumType!(This*, string)[int]]));
}

// Supports nested self-referential SumTypes
@safe unittest {
	import std.typecons : Tuple, Flag;
	alias Nat = SumType!(Flag!"0", Tuple!(This*));
	static assert(__traits(compiles, SumType!(Nat)));
	static assert(__traits(compiles, SumType!(Nat*, Tuple!(This*, This*))));
}
  
// Github issue #24
@safe unittest {
	assert(__traits(compiles, () @nogc {
		int acc = 0;
		SumType!int(1).match!((int x) => acc += x);
	}));
}
