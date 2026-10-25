module wpl.operators.functions;

import std.math;
import std.stdio;
import std.format;
import wpl.error;
import wpl.value;
import wpl.parser;
import wpl.interpreter;

static Value Function(Value pleft, Value pright, Interpreter env) {
	auto left  = cast(ArrayValue) pleft;
	auto right = (cast(LambdaValue) pright).value;

	auto func = new FunctionValue();
	foreach (ref arg ; left.values) {
		auto var     = cast(VariableValue) arg;
		func.params ~= var.value;
	}

	func.value = right;
	return func;
}

static Value Call(Value pleft, Value pright, Interpreter env) {
	auto left  = cast(FunctionValue) pleft;
	auto right = cast(ArrayValue) pright;

	if (right.values.length != left.params.length) {
		throw new OperatorException(format(
			"Expected %d parameters, got %d", right.values.length,
			left.params.length
		));
	}

	Value ret;

	if (left.builtIn) {
		ret = left.func(right.values, env);
	}
	else {
		env.AddScope();
		foreach (i, ref param ; right.values) {
			// env.variables[left.params[i]] = Variable(param, env.topScope);
			env.SetLocal(left.params[i], Variable(param));
		}
		
		ret = env.Evaluate(left.value, true);
		env.RemoveScope();
	}

	return ret;
}

static Value Extract(Value pleft, Value pright, Interpreter env) {
	auto left  = (cast(LambdaValue) pleft).value;
	auto right = (cast(IntegerValue) pright).value;

	auto ret = new LambdaValue();

	if (left.type != NodeType.Expression) {
		throw new OperatorException("Must pass lambda containing expression to extract");
		// TODO: maybe allow this
	}

	auto expr = cast(ExpressionNode) left;

	ret.value = right == 0? expr.left : expr.right;

	return ret;
}

static Value WriteLeft(Value pleft, Value pright, Interpreter env) {
	auto left  = (cast(LambdaValue) pleft).value;
	auto right = (cast(LambdaValue) pright).value;

	auto ret = new LambdaValue();

	if (left.type != NodeType.Expression) {
		throw new OperatorException("Must pass lambda containing expression to overwrite");
	}
	
	auto oldExpr = cast(ExpressionNode) left;

	auto expr  = new ExpressionNode(oldExpr.info);
	expr.left  = right;
	expr.op    = oldExpr.op;
	expr.right = oldExpr.right;

	ret.value = expr;
	return ret;
}

static Value WriteRight(Value pleft, Value pright, Interpreter env) {
	auto left  = (cast(LambdaValue) pleft).value;
	auto right = (cast(LambdaValue) pright).value;

	auto ret = new LambdaValue();

	if (left.type != NodeType.Expression) {
		throw new OperatorException("Must pass lambda containing expression to overwrite");
	}

	auto oldExpr = cast(ExpressionNode) left;

	auto expr  = new ExpressionNode(oldExpr.info);
	expr.left  = oldExpr.left;
	expr.op    = oldExpr.op;
	expr.right = right;

	ret.value = expr;
	return ret;
}

static Value ChangeOp(Value pleft, Value pright, Interpreter env) {
	auto left  = (cast(LambdaValue) pleft).value;
	auto right = (cast(StringValue) pright).value;

	auto ret = new LambdaValue();

	if (left.type != NodeType.Expression) {
		throw new OperatorException("Must pass lambda containing expression to overwrite");
	}

	auto oldExpr = cast(ExpressionNode) left;

	auto expr  = new ExpressionNode(oldExpr.info);
	expr.left  = oldExpr.left;
	expr.op    = right;
	expr.right = oldExpr.right;

	ret.value = expr;
	return ret;
}

static Value LambdaCalculus(Value pleft, Value pright, Interpreter env) {
	if (pleft.type != ValueType.Variable) {
		throw new OperatorException("Lambda calculus operator expects parameter name");
	}
	if (pright.type != ValueType.Lambda) {
		throw new OperatorException("Lambda calculus operator expects return thing");
	}

	auto left  = (cast(VariableValue) pleft).value;
	auto right = (cast(LambdaValue) pright).value;

	auto func    = new FunctionValue();
	func.params  = [left];
	func.builtIn = false;
	func.value   = right;
	return func;
}
