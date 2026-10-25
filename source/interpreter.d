module wpl.interpreter;

import std.stdio;
import std.algorithm;
import core.stdc.stdlib;
import wpl.error;
import wpl.value;
import wpl.parser;
import wpl.builtins;
import wpl.exception;
import wpl.operators.io;
import wpl.operators.array;
import wpl.operators.logic;
import wpl.operators.floats;
import wpl.operators.strings;
import wpl.operators.integer;
import wpl.operators.pointer;
import wpl.operators.structure;
import wpl.operators.functions;
import wpl.operators.variables;
import wpl.operators.imperative;

struct Variable {
	Value value;
	bool  constant;

	this(Value pvalue) {
		value = pvalue;
	}

	this(Value pvalue, bool pconstant) {
		value    = pvalue;
		constant = pconstant;
	}

	static Variable Constant(Value value) {
		return Variable(value, true);
	}
}

alias OperatorFunc = Value function(Value, Value, Interpreter);

class OperatorException : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__) {
		super(msg, file, line);
	}
}

struct Operator {
	string       name;
	ValueType    left;
	ValueType    right;
	OperatorFunc func;
	bool         strict;

	this(string pname, ValueType pleft, ValueType pright, OperatorFunc pfunc) {
		name      = pname;
		left      = pleft;
		right     = pright;
		func      = pfunc;
		strict    = true;
	}

	this(string pname, OperatorFunc pfunc) {
		name      = pname;
		func      = pfunc;
		strict    = false;
	}
}

struct OpMeta {
	bool evalLeft;
	bool evalRight;
}

class Interpreter {
	Variable[string][] scopes;
	Operator[]         ops;
	OpMeta[string]     opMeta;
	string[]           thisFile;

	this() {
		// create global scope
		AddScope();
	
		// default variables
		SetVariable("stdout", Variable(Value.File(stdout)));
		SetVariable("stderr", Variable(Value.File(stderr)));
		SetVariable("stdin",  Variable(Value.File(stdin)));
		SetVariable("unit",   Variable(Value.Unit()));
		SetVariable("left",   Variable(Value.Integer(0)));
		SetVariable("right",  Variable(Value.Integer(1)));

		// strict operators
		AddOp("+",   ValueType.Integer,      ValueType.Integer,      &AddInt);
		AddOp("-",   ValueType.Integer,      ValueType.Integer,      &SubInt);
		AddOp("*",   ValueType.Integer,      ValueType.Integer,      &MulInt);
		AddOp("/",   ValueType.Integer,      ValueType.Integer,      &DivInt);
		AddOp("^",   ValueType.Integer,      ValueType.Integer,      &PowInt);
		AddOp("%",   ValueType.Integer,      ValueType.Integer,      &ModInt);
		AddOp("<",   ValueType.Integer,      ValueType.Integer,      &IntLess);
		AddOp("<=",  ValueType.Integer,      ValueType.Integer,      &IntLessE);
		AddOp(">",   ValueType.Integer,      ValueType.Integer,      &IntGreater);
		AddOp(">=",  ValueType.Integer,      ValueType.Integer,      &IntGreaterE);
		AddOp(".s",  ValueType.File,         ValueType.String,       &WriteString);
		AddOp(".d",  ValueType.File,         ValueType.Integer,      &WriteDecimal);
		AddOp("==",  ValueType.Integer,      ValueType.Integer,      &IntEquals);
		AddOp("/=",  ValueType.Integer,      ValueType.Integer,      &IntNotEquals);
		AddOp("/=",  ValueType.Integer,      ValueType.Integer,      &IntNotEquals);
		AddOp("?",   ValueType.Integer,      ValueType.Lambda,       &If);
		AddOp(",",   ValueType.File,         ValueType.Integer,      &Read);
		AddOp(",n",  ValueType.File,         ValueType.Integer,      &ReadLine);
		AddOp("+",   ValueType.String,       ValueType.String,       &AddString);
		AddOp("-",   ValueType.String,       ValueType.Integer,      &StringLength);
		AddOp("==",  ValueType.String,       ValueType.String,       &EqualsString);
		AddOp("/=",  ValueType.String,       ValueType.String,       &NotEqualsString);
		AddOp("@",   ValueType.Lambda,       ValueType.Lambda,       &While);
		AddOp("+",   ValueType.Array,        ValueType.Integer,      &AddArray);
		AddOp("+",   ValueType.Array,        ValueType.String,       &AddArray);
		AddOp("+",   ValueType.Array,        ValueType.Lambda,       &AddArray);
		AddOp("+",   ValueType.Array,        ValueType.Array,        &AddArray);
		AddOp(":",   ValueType.Array,        ValueType.Integer,      &ArrayIndex);
		AddOp("-",   ValueType.Array,        ValueType.Integer,      &ArrayLength);
		AddOp(":=",  ValueType.Reference,    ValueType.Integer,      &RefAssign);
		AddOp(":=",  ValueType.Reference,    ValueType.String,       &RefAssign);
		AddOp(":=",  ValueType.Reference,    ValueType.Lambda,       &RefAssign);
		AddOp(":=",  ValueType.Reference,    ValueType.Array,        &RefAssign);
		AddOp(":",   ValueType.Reference,    ValueType.Integer,      &DeRef);
		AddOp(":",   ValueType.Reference,    ValueType.String,       &DeRef);
		AddOp(":",   ValueType.Reference,    ValueType.Lambda,       &DeRef);
		AddOp(":",   ValueType.Reference,    ValueType.Array,        &DeRef);
		AddOp("=>",  ValueType.Array,        ValueType.Lambda,       &Function);
		AddOp("!",   ValueType.Function,     ValueType.Array,        &Call);
		AddOp("&&",  ValueType.Lambda,       ValueType.Lambda,       &BoolAnd);
		AddOp("||",  ValueType.Lambda,       ValueType.Lambda,       &BoolOr);
		AddOp("&$",  ValueType.Pointer,      ValueType.Variable,     &PointerType);
		AddOp("&.",  ValueType.Pointer,      ValueType.Integer,      &PointerWrite);
		AddOp("&,",  ValueType.Pointer,      ValueType.Integer,      &PointerRead);
		AddOp("+",   ValueType.Pointer,      ValueType.Integer,      &PointerAdd);
		AddOp("-",   ValueType.Pointer,      ValueType.Integer,      &PointerSub);
		AddOp(":",   ValueType.String,       ValueType.Integer,      &IndexString);
		AddOp(":=",  ValueType.CharRef,      ValueType.String,       &WriteChar);
		AddOp(":",   ValueType.CharRef,      ValueType.String,       &DerefChar);
		AddOp("&",   ValueType.Integer,      ValueType.Integer,      &AndInt);
		AddOp("|",   ValueType.Integer,      ValueType.Integer,      &OrInt);
		AddOp("!",   ValueType.Integer,      ValueType.Integer,      &XorInt);
		AddOp("<<",  ValueType.Integer,      ValueType.Integer,      &LShiftInt);
		AddOp(">>",  ValueType.Integer,      ValueType.Integer,      &RShiftInt);
		AddOp(",b",  ValueType.File,         ValueType.Integer,      &ReadByte);
		AddOp("%",   ValueType.String,       ValueType.String,       &StringFormat);
		AddOp("%",   ValueType.String,       ValueType.Integer,      &StringFormat);
		AddOp("/",   ValueType.Array,        ValueType.Integer,      &ArrayRemove);
		AddOp("$",   ValueType.StructureDef, ValueType.Variable,     &Structure);
		AddOp("$=",  ValueType.Variable,     ValueType.StructureDef, &AssignStructure);
		AddOp("$:",  ValueType.Structure,    ValueType.Variable,     &StructMember);
		AddOp("$::", ValueType.Structure,    ValueType.Variable,     &StructMemberValue);
		AddOp("::",  ValueType.Array,        ValueType.Integer,      &ArrayIndexValue);
		AddOp("+",   ValueType.Float,        ValueType.Float,        &AddFloat);
		AddOp("-",   ValueType.Float,        ValueType.Float,        &SubFloat);
		AddOp("*",   ValueType.Float,        ValueType.Float,        &MulFloat);
		AddOp("/",   ValueType.Float,        ValueType.Float,        &DivFloat);
		AddOp("^",   ValueType.Float,        ValueType.Float,        &PowFloat);
		AddOp("%",   ValueType.Float,        ValueType.Float,        &ModFloat);
		AddOp("<",   ValueType.Float,        ValueType.Float,        &FloatLess);
		AddOp("<=",  ValueType.Float,        ValueType.Float,        &FloatLessE);
		AddOp(">",   ValueType.Float,        ValueType.Float,        &FloatGreater);
		AddOp(">=",  ValueType.Float,        ValueType.Float,        &FloatGreaterE);
		AddOp(".f",  ValueType.File,         ValueType.Float,        &WriteFloat);
		AddOp("~",   ValueType.Lambda,       ValueType.Integer,      &Extract);
		AddOp("<*",  ValueType.Lambda,       ValueType.Lambda,       &WriteLeft);
		AddOp(">*",  ValueType.Lambda,       ValueType.Lambda,       &WriteRight);
		AddOp(".*",  ValueType.Lambda,       ValueType.String,       &ChangeOp);
		AddOp(",",   ValueType.Variable,     ValueType.Lambda,       &LambdaCalculus);

		// not strict operators
		AddOp(";", &Chain);
		AddOp("=", &Assign);

		// op meta
		SetOpMeta("=",   false, true);
		SetOpMeta("=>",  false, true);
		SetOpMeta("&$",  true,  false);
		SetOpMeta("$",   true,  false);
		SetOpMeta("$=",  false, true);
		SetOpMeta("$:",  true,  false);
		SetOpMeta("$::", true,  false);
		SetOpMeta(",",   false, false);

		// builtin functions
		AddFunction("time",         &Time,        0);
		AddFunction("open",         &Open,        2);
		AddFunction("flush",        &Flush,       1);
		AddFunction("close",        &Close,       1);
		AddFunction("mkdir",        &Mkdir,       1);
		AddFunction("fexists",      &FExists,     1);
		AddFunction("alloc",        &Alloc,       1);
		AddFunction("realloc",      &Realloc,     2);
		AddFunction("free",         &Free,        1);
		AddFunction("import",       &Import,      1);
		AddFunction("export",       &Export,      1);
		AddFunction("srand",        &SRand,       1);
		AddFunction("rand",         &Rand,        0);
		AddFunction("exit",         &Exit,        1);
		AddFunction("fseek",        &FSeek,       3);
		AddFunction("ftell",        &FTell,       1);
		AddFunction("char_code",    &CharCode,    1);
		AddFunction("as_char",      &AsChar,      1);
		AddFunction("float",        &Float,       1);
		AddFunction("int",          &Int,         1);
		AddFunction("extract",      &ExtractFunc, 1);
		AddFunction("read_program", &ReadProgram, 1);

		// constnats
		AddConstant("SEEK_SET", Value.Integer(SEEK_SET));
		AddConstant("SEEK_CUR", Value.Integer(SEEK_CUR));
		AddConstant("SEEK_END", Value.Integer(SEEK_END));
		AddConstant("struct",   Value.StructureDef([]));
		AddConstant("range",    Value.StructureDef(["start", "end", "step"]));
	}

	void AddOp(string name, ValueType left, ValueType right, OperatorFunc func) {
		ops          ~= Operator(name, left, right, func);
		opMeta[name]  = OpMeta(true, true);
	}

	void AddOp(string name, OperatorFunc func) {
		ops          ~= Operator(name, func);
		opMeta[name]  = OpMeta(true, true);
	}

	void SetOpMeta(string name, bool left, bool right) {
		opMeta[name] = OpMeta(left, right);
	}

	void AddFunction(string name, BuiltInFunc func, size_t argsLen) {
		auto value          = new FunctionValue();
		value.builtIn       = true;
		value.func          = func;
		value.params.length = argsLen;
		SetVariable(name, Variable(value));
	}

	void AddConstant(string name, Value value) {
		SetVariable(name, Variable.Constant(value));
	}

	bool VariableExists(string name) {
		// return (name in scopes[0]) || (name in scopes[$ - 1]);
		foreach (ref scopeIt ; scopes) {
			if (name in scopeIt) return true;
		}

		return false;
	}

	Variable GetVariable(string name) {
		// if (name in scopes[$ - 1]) return scopes[$ - 1][name];
		// return scopes[0][name];

		foreach (ref scopeIt ; scopes) {
			if (name in scopeIt) return scopeIt[name];
		}

		assert(0);
	}

	Value* GetVariableRef(string name) {
		// if (name in scopes[$ - 1]) return &scopes[$ - 1][name].value;
		// return &scopes[0][name].value;

		foreach (ref scopeIt ; scopes) {
			if (name in scopeIt) return &scopeIt[name].value;
		}

		assert(0);
	}

	void SetVariable(string name) {
		// if (name in scopes[0]) {
		// 	scopes[0][name] = Variable(Value.Unit());
		// }
		// else {
		// 	scopes[$ - 1][name] = Variable(Value.Unit());
		// }

		foreach (ref scopeIt ; scopes) {
			if (name in scopeIt) {
				scopeIt[name] = Variable(Value.Unit());
			}
		}

		scopes[$ - 1][name] = Variable(Value.Unit());
	}

	void SetVariable(string name, Variable value) {
		foreach (ref scopeIt ; scopes) {
			if (name in scopeIt) {
				scopeIt[name] = value;
			}
		}

		scopes[$ - 1][name] = value;
	}

	void SetLocal(string name, Variable value) {
		scopes[$ - 1][name] = value;
	}

	bool LocalExists(string name) {
		return name in scopes[$ - 1]? true : false;
	}

	Variable GetLocal(string name) {
		return scopes[$ - 1][name];
	}

	void AddScope() {
		scopes ~= new Variable[string];
	}

	void RemoveScope() {
		scopes = scopes[0 .. $ - 1];
	}

	void AddArgs(string[] args) {
		auto argv = new ArrayValue();

		foreach (ref arg ; args) {
			argv.values ~= Value.String(arg);
		}

		SetVariable("argv", Variable(argv));
	}

	void AssertVariable(string name, ErrorInfo info) {
		if (!VariableExists(name)) {
			ErrorBegin(info);
			stderr.writefln("No such variable: %s", name);
			Fatal();
		}
	}

	bool IsType(string str) {
		auto types = [
			"unit", "int", "string", "file", "lambda", "ref", "array", "func", "ptr"
		];

		return types.canFind(str)? true : false;
	}

	Value Evaluate(Node pnode, bool evalVariables) {
		if (pnode is null) {
			return Value.Unit();
		}
	
		switch (pnode.type) {
			case NodeType.Integer: {
				auto node = cast(IntegerNode) pnode;
				
				return Value.Integer(node.value);
			}
			case NodeType.String: {
				auto node = cast(StringNode) pnode;

				return Value.String(node.value);
			}
			case NodeType.Identifier: {
				auto node = cast(IdentifierNode) pnode;

				if (evalVariables) {
					AssertVariable(node.name, node.info);
					return GetVariable(node.name).value;
				}
				else {
					return Value.Variable(node.name);
				}
			}
			case NodeType.Lambda: {
				auto node = cast(LambdaNode) pnode;

				return Value.Lambda(node.expr);
			}
			case NodeType.Array: {
				auto node = cast(ArrayNode) pnode;
				auto ret  = Value.Array([]);

				foreach (ref node2 ; node.values) {
					ret.values ~= Evaluate(node2, evalVariables);
				}

				return ret;
			}
			case NodeType.Float: {
				auto node = cast(FloatNode) pnode;

				return Value.Float(node.value);
			}
			case NodeType.Expression: {
				auto node = cast(ExpressionNode) pnode;

				Operator op;
				Value    left;
				Value    right;
				bool     found;
				OpMeta   meta;

				if (node.op !in opMeta) goto opNotFound;

				meta = opMeta[node.op];

				left  = Evaluate(node.left, meta.evalLeft);
				right = Evaluate(node.right, meta.evalRight);
				
				foreach (ref iop ; ops) {
					if (iop.strict) {
						if (
							(iop.name == node.op) &&
							(iop.left == left.type) &&
							(iop.right == right.type) 
						) {
							found = true;
							op    = iop;
							break;
						}
					}
					else {
						if (iop.name == node.op) {
							found = true;
							op    = iop;
							break;
						}
					}
				}

				opNotFound:
				if (!found) {
					ErrorBegin(node.info);
					stderr.writefln(
						"No operator matches %s %s %s", left.type, node.op, right.type
					);
					Fatal();
				}

				Value ret;
				
				try {
					ret = op.func(left, right, this);
				}
				catch (OperatorException e) {
					ErrorBegin(node.info);
					stderr.writef("(%s) ", node.op);
					stderr.writeln(e.msg);
					Fatal();
				}

				return ret;
			}
			default: assert(0);
		}
	}
}
