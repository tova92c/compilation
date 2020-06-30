%{
#include <stdio.h>
#include <cstdio>
#include <iostream>
#include <sstream>
#include "hw5_semantics.hpp"
#include "hw5_ir.hpp"

int yylex();
void yyerror(const char*);
extern int yylineno;
StackClass stack_symbol; 
%}

%token VOID INT BYTE B BOOL TRUE FALSE RETURN WHILE BREAK CONTINUE;
%nonassoc SC COMMA LBRACE RBRACE ID NUM STRING;
%right ASSIGN;
%left OR AND;
%left RELOP1;
%nonassoc RELOP2;
%left BINOP MULTOP;
%left RPAREN LPAREN;
%right IF ELSE NOT;
%%


Program: G Funcs {
					if(!stack_symbol.symbol_tables_contains_function("main")){
						errorMainMissing();
						exit(0);
					}
					Param* p = stack_symbol.get_function("main");
					if(p->return_type != "VOID" || p->argument.size()!=0){
						errorMainMissing();
						exit(0);
					}
					stack_symbol.remove_scope();
					CodeBuffer::instance().printGlobalBuffer();
					CodeBuffer::instance().printCodeBuffer();
					exit(1);
					};

G:            {					
				stack_symbol.add_scope("global_scope");
				CodeBuffer::instance().emitGlobal("@.int_specifier = constant [4 x i8] c\"%d\\0A\\00\"");
				CodeBuffer::instance().emitGlobal("@.str_specifier = constant [4 x i8] c\"%s\\0A\\00\"");
				CodeBuffer::instance().emitGlobal("@.error_div_by_zero = constant [23 x i8] c\"Error division by zero\\00\"");
				CodeBuffer::instance().emitGlobal("declare void @exit(i32)");
				CodeBuffer::instance().emitGlobal("declare i32 @printf(i8*, ...)");

				stack_symbol.add_func("printi", "VOID");
				CodeBuffer::instance().emitGlobal("define void @printi(i32) {");
				CodeBuffer::instance().emitGlobal("call i32 (i8*, ...) @printf(i8* getelementptr ([4 x i8], [4 x i8]* @.int_specifier, i32 0, i32 0), i32 %0)");
				CodeBuffer::instance().emitGlobal("ret void	}");
				
				stack_symbol.add_func("print", "VOID");
				CodeBuffer::instance().emitGlobal("define void @print(i8*) {");
				CodeBuffer::instance().emitGlobal("call i32 (i8*, ...) @printf(i8* getelementptr ([4 x i8], [4 x i8]* @.str_specifier, i32 0, i32 0), i8* %0)");
				CodeBuffer::instance().emitGlobal("ret void	}");
				};
Funcs: /*epsilon*/ 
     | FuncDecl Funcs;

	 
FuncDecl: RetType ID
				{ 
					if((stack_symbol.symbol_tables_contains(((Id*)$2)->str)) || (stack_symbol.symbol_tables_contains_function(((Id*)$2)->str))){
							errorDef(yylineno, ((Id*)$2)->str);
							exit(0);
					}
					stack_symbol.add_scope("function");
					stack_symbol.add_func(((Id*)$2)->str,$1->type);						
				}
			LPAREN Formals RPAREN	
				{	
					CodeBuffer::instance().emit("define " + stack_symbol.update($1->type) + " @" + ((Id*)$2)->str + stack_symbol.print_arguments() + " {");
					CodeBuffer::instance().emit("%MyStack = alloca [50 x i32]");
					Param* func = stack_symbol.get_function(((Id*)$2)->str);
					CodeBuffer::instance().emit("%args = alloca [50 x i32]");
					CodeBuffer::instance().emit("%bool = alloca i1");
					for(int i=0; i < func->argument.size(); i++){
						CodeBuffer::instance().emit("%arg_" + to_string(i) + " = getelementptr [50 x i32],[50 x i32]* %args, i32 0, i32 "+ to_string(i));
						if(func->argument[i] == "BOOL")
							CodeBuffer::instance().emit("%temp" + to_string(i) + " = zext i1 %" + to_string(i) + " to i32");
						else if(func->argument[i] == "BYTE")
							CodeBuffer::instance().emit("%temp" + to_string(i) + " = zext i8 %" + to_string(i) + " to i32");
						else 
							CodeBuffer::instance().emit("%temp" + to_string(i) + " = add i32 0, %" + to_string(i));
						CodeBuffer::instance().emit("store i32 %temp" + to_string(i) +", i32* %arg_" + to_string(i));
					}
				}	

			LBRACE Statements RBRACE 
				{
					stack_symbol.remove_scope();
					if(((Node*)$1)->type == "VOID")
						CodeBuffer::instance().emit("ret void	}");
				};

RetType: Type    {$$ = $1;} 
         | VOID   { $$ = new Node();
					$$ ->type = "VOID" ;};
		 
Formals: /*epsilon*/ | FormalsList;

FormalsList: FormalDecl 
             | FormalDecl COMMA FormalsList;
			 
FormalDecl: Type ID
				{
					if((stack_symbol.symbol_tables_contains(((Id*)$2)->str)) || (stack_symbol.symbol_tables_contains_function(((Id*)$2)->str))){
						errorDef(yylineno, ((Id*)$2)->str);
						exit(0);
					}
					stack_symbol.insert_param_for_func(((Id*)$2)->str, $1->type);	
				};
			 

Statements: Statement {$$=$1;}
          | Statements Statement
			{
				((Stmnt*)$$)->breakList = CodeBuffer::instance().merge(((Stmnt*)$1)->breakList, ((Stmnt*)$2)->breakList);
				((Stmnt*)$$)->continueList = CodeBuffer::instance().merge(((Stmnt*)$1)->continueList, ((Stmnt*)$2)->continueList);
			};


Statement: RestStatement {$$=$1;}
          |IF {stack_symbol.add_scope("if");}
		  LPAREN BoolExp RPAREN M Statement scopeClose
		  {
			CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, ((Node*)$6)->str);
			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> next_list = CodeBuffer::instance().makelist(temp);
			string next = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().bpatch(((Expression*)$3)->false_list, next);
			CodeBuffer::instance().bpatch(next_list, next);
			$$ = $7;
		  }
	      |IF {stack_symbol.add_scope("if");}
		  LPAREN BoolExp RPAREN M Statement scopeClose ELSE {stack_symbol.add_scope("else");} N M Statement scopeClose
		  {
			CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, ((Node*)$6)->str);
			CodeBuffer::instance().bpatch(((Expression*)$3)->false_list,((Node*)$12)->str);
			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> bp = CodeBuffer::instance().makelist(temp);
			string next = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().bpatch(((MarkerN*)$11)->nextList, next);
			CodeBuffer::instance().bpatch(bp, next);
			$$ = $7;
			//((Stmnt*)$$)->breakList = CodeBuffer::instance().merge(((Stmnt*)$7)->breakList, ((Stmnt*)$13)->breakList);						
			//((Stmnt*)$$)->continueList = CodeBuffer::instance().merge(((Stmnt*)$7)->continueList, ((Stmnt*)$13)->continueList);
		  }
		  |WHILE {stack_symbol.add_scope("while");}
		  LPAREN BoolExp RPAREN M Statement scopeClose
		  {
			CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, ((Node*)$6)->str);
			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> next_list = CodeBuffer::instance().makelist(temp);
			string next = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().bpatch(((Expression*)$3)->false_list, next);
			CodeBuffer::instance().bpatch(next_list, next);
			$$ = $7;
		  }
		  |WHILE {stack_symbol.add_scope("while");}
		  LPAREN BoolExp RPAREN M Statement scopeClose ELSE {stack_symbol.add_scope("else");} N M Statement scopeClose
		  {
			CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, ((Node*)$6)->str);
			CodeBuffer::instance().bpatch(((Expression*)$3)->false_list,((Node*)$12)->str);
			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> bp = CodeBuffer::instance().makelist(temp);
			string next = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().bpatch(((MarkerN*)$11)->nextList, next);
			CodeBuffer::instance().bpatch(bp, next);
			$$ = $7;
			//((Stmnt*)$$)->breakList = CodeBuffer::instance().merge(((Stmnt*)$7)->breakList, ((Stmnt*)$13)->breakList);						
			//((Stmnt*)$$)->continueList = CodeBuffer::instance().merge(((Stmnt*)$7)->continueList, ((Stmnt*)$13)->continueList);
		  }
		  | BREAK SC {
				if(!stack_symbol.check_after_while()){
					errorUnexpectedBreak(yylineno);
					exit(0);
				}
				$$ = new Stmnt();
				int bp = CodeBuffer::instance().emit("br label @");
				LabelPair temp (bp,FIRST);
				((Stmnt*)$$)->breakList = CodeBuffer::instance().makelist(temp);
			}
		   | CONTINUE SC{
				if(!stack_symbol.check_after_while()){
					errorUnexpectedContinue(yylineno);
					exit(0);
				}
				$$ = new Stmnt();
				int bp = CodeBuffer::instance().emit("br label @");
				LabelPair temp (bp,FIRST);
				((Stmnt*)$$)->breakList = CodeBuffer::instance().makelist(temp);
		 };

scopeClose : { stack_symbol.remove_scope();};


BoolExp: Exp { if (((Expression*)$1)->type != "BOOL") {
				errorMismatch(yylineno);
				exit(0);
			   }
			 };

RestStatement: LBRACE{stack_symbol.add_scope("default");}
			Statements RBRACE {
					/*print scope*/
					/*stack_symbol.print_scope();*/
					stack_symbol.remove_scope();
					$$ = $3;
				}
			| Type ID SC{
							if((stack_symbol.symbol_tables_contains(((Id*)$2)->str)) || 
								(stack_symbol.symbol_tables_contains_function(((Id*)$2)->str))){
								errorDef(yylineno, ((Id*)$2)->str);
								exit(0);
							}
							int offset = stack_symbol.insert_id(((Id*)$2)->str, $1->type);
							TempVar var = TempVar();
							CodeBuffer::instance().emit(var.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
							CodeBuffer::instance().emit("store i32 0, i32* " + var.name);
							$$ = new Stmnt();
						}
			| Type ID ASSIGN Exp SC{
						if((stack_symbol.symbol_tables_contains(((Id*)$2)->str)) || 
						 (stack_symbol.symbol_tables_contains_function(((Id*)$2)->str))){
							errorDef(yylineno, ((Id*)$2)->str);
							exit(0);
						}
						if($1->type != ((Expression*)$4)->type){
							if($1->type != "INT"){
								errorMismatch(yylineno);
								exit(0);
							} else if (((Expression*)$4)->type != "BYTE"){
							errorMismatch(yylineno);
								exit(0);
							} 
						}
						int offset = stack_symbol.insert_id(((Id*)$2)->str, $1->type);
						TempVar var = ((Expression*)$4)->place;
						TempVar var1 = TempVar();
						TempVar var2 = TempVar();
						if(((Expression*)$4)->type == "BOOL"){
							string falseLabel = CodeBuffer::instance().genLabel();
							CodeBuffer::instance().emit(var1.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
							CodeBuffer::instance().emit("store i32 0, i32* " + var1.name);
							int loc1 = CodeBuffer::instance().emit("br label @");
							LabelPair temp (loc1,FIRST);
							vector<pair<int,BranchLabelIndex>> bp = CodeBuffer::instance().makelist(temp);
							string trueLabel = CodeBuffer::instance().genLabel();
							CodeBuffer::instance().emit(var2.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
							CodeBuffer::instance().emit("store i32 1, i32* " + var2.name);
							int loc2 = CodeBuffer::instance().emit("br label @");
							LabelPair temp1 (loc2,FIRST);
							vector<pair<int,BranchLabelIndex>> bp1 = CodeBuffer::instance().makelist(temp1);
							string nextLabel = CodeBuffer::instance().genLabel();
							CodeBuffer::instance().bpatch(((Expression*)$4)->true_list, trueLabel);
							CodeBuffer::instance().bpatch(((Expression*)$4)->false_list, falseLabel);
							CodeBuffer::instance().bpatch(bp, nextLabel);
							CodeBuffer::instance().bpatch(bp1, nextLabel);
						}else{
							TempVar var3 = TempVar();
							CodeBuffer::instance().emit(var3.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
							CodeBuffer::instance().emit("store i32 " + var.name + ", i32* " + var3.name);
						}
						$$ = new Stmnt();	
					}
			| ID ASSIGN Exp SC 
				{
					if(!(stack_symbol.symbol_tables_contains(((Id*)$1)->str))){
						errorUndef(yylineno, ((Id*)$1)->str);
						exit(0);
					}
					if(stack_symbol.symbol_tables_contains_function(((Id*)$1)->str)){
						errorMismatch(yylineno);
						exit(0);
					}
					Param* p = stack_symbol.get_param(((Id*)$1)->str);
					if(p->type != ((Expression*)$3)->type){
						if(p->type != "INT" && p->type != "BYTE" && p->type != "STRING" && p->type != "BOOL")
							exit(0);
						if(p->type != ((Expression*)$3)->type){
							if(((Expression*)$3)->type != "INT" && ((Expression*)$3)->type != "BYTE" && ((Expression*)$3)->type != "STRING" && ((Expression*)$3)->type != "BOOL")
								exit(0);
						}
						if(p->type != "INT"){
							errorMismatch(yylineno);
							exit(0);
						} else if (((Expression*)$3)->type != "BYTE"){
							errorMismatch(yylineno);
							exit(0);
						} 
					}
					int offset = p->offset;
					TempVar var = ((Expression*)$3)->place;
					TempVar var1 = TempVar();
					if (((Expression*)$3)->type == "BOOL") {
						TempVar var2 = TempVar();
						string falseLabel = CodeBuffer::instance().genLabel();
						CodeBuffer::instance().emit(var1.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
						CodeBuffer::instance().emit("store i32 0, i32* " + var1.name);
						int loc1 = CodeBuffer::instance().emit("br label @");
						LabelPair temp (loc1,FIRST);
						vector<LabelPair> bp = CodeBuffer::instance().makelist(temp);
						string trueLabel = CodeBuffer::instance().genLabel();
						CodeBuffer::instance().emit(var2.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
						CodeBuffer::instance().emit("store i32 1, i32* " + var2.name);
						int loc2 = CodeBuffer::instance().emit("br label @");
						LabelPair temp1 (loc2,FIRST);
						vector<LabelPair> bp1 = CodeBuffer::instance().makelist(temp1);
						string nextLabel = CodeBuffer::instance().genLabel();
						CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, trueLabel);
						CodeBuffer::instance().bpatch(((Expression*)$3)->false_list, falseLabel);
						CodeBuffer::instance().bpatch(bp, nextLabel);
						CodeBuffer::instance().bpatch(bp1, nextLabel);
					}
					else{
						TempVar var3 = TempVar();
						if(offset >= 0){
							CodeBuffer::instance().emit(var3.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
							CodeBuffer::instance().emit("store i32 " + var.name + ", i32* " + var3.name);
						}
						else{
							offset = 0 - offset - 1;
							CodeBuffer::instance().emit(var3.name + " = getelementptr [50 x i32],[50 x i32]* %args, i32 0, i32 "+ to_string(offset));
							CodeBuffer::instance().emit("store i32 " + var.name + ", i32* " + var3.name);
						}
					}
					$$ = new Stmnt();
				}
		 | Call SC	{$$ = new Stmnt();}
		 | RETURN SC{
		    string type_to_check = stack_symbol.tables_stack[0].paramaters.back().return_type;
			if(type_to_check != "VOID"){
				errorMismatch(yylineno);
				exit(0);
			}
			CodeBuffer::instance().emit("ret void");
			$$ = new Stmnt(true);
		 } 
		 | RETURN Exp SC {
			string type_to_check = stack_symbol.tables_stack[0].paramaters.back().return_type;
			if(type_to_check == "VOID"){
				errorMismatch(yylineno);
					exit(0);
			}
			if(type_to_check != ((Expression*)$2)->type ){
				if(!(type_to_check == "INT" && ((Expression*)$2)->type == "BYTE")){
					errorMismatch(yylineno);
					exit(0);
				}
			}
			TempVar var = ((Expression*)$2)->place;
			TempVar temp1 = TempVar();
			if (((Expression*)$2)->type == "BOOL"){
				string falseLabel = CodeBuffer::instance().genLabel();
				CodeBuffer::instance().emit("ret i1 0	}");
				string trueLabel = CodeBuffer::instance().genLabel();
				CodeBuffer::instance().emit("ret i1 1	}");
				CodeBuffer::instance().bpatch(((Expression*)$2)->true_list, trueLabel);
				CodeBuffer::instance().bpatch(((Expression*)$2)->false_list, falseLabel);
			}
			if(type_to_check == "INT")
				CodeBuffer::instance().emit("ret i32 " + var.name);
			if(type_to_check == "BYTE"){
					CodeBuffer::instance().emit(temp1.name + " = trunc i32 " + var.name + " to i8");
					CodeBuffer::instance().emit("ret i8 " + temp1.name);
			}
			$$ = new Stmnt(true);
		 
		 }
Call: ID LPAREN ExpList RPAREN 
	{	
		if(!(stack_symbol.symbol_tables_contains_function(((Id*)$1)->str))){
		     errorUndefFunc(yylineno,((Id*)$1)->str );
			 exit(0);
		}
		Param* func = stack_symbol.get_function(((Id*)$1)->str);
		if(func->argument.size() != ((ExpList*)$3)->types.size()){
			errorPrototypeMismatch(yylineno, ((Id*)$1)->str, func->argument);
			exit(0);
		}
		for(int i = 0; i < func->argument.size(); i++){
			if(func->argument[i] != ((ExpList*)$3)->types[func->argument.size() -i -1 ]){
				if(((ExpList*)$3)->types[func->argument.size() -i -1 ] != "BYTE"){
					errorPrototypeMismatch(yylineno, ((Id*)$1)->str, func->argument);
					exit(0);
				} else if(func->argument[i] != "INT"){
					errorPrototypeMismatch(yylineno, ((Id*)$1)->str, func->argument);
					exit(0);
				} else {}
			}  
		}
		$$= new Expression(func->return_type);
		stringstream res;
		res << "(";
		for(int i = func->argument.size()-1 ; i >= 0 ; --i) { 
			res << stack_symbol.update(((ExpList*)$3)->types[i]);
			res << " ";
			if(((ExpList*)$3)->types[i] == "BYTE"){
				TempVar temp = TempVar();
				CodeBuffer::instance().emit(temp.name +  " = trunc i32 " + ((ExpList*)$3)->vars[i] + " to i8");
				res << temp.name;
			}
			else
				res << ((ExpList*)$3)->vars[i];
			if (i - 1 >= 0)
				res << ",";
		}
		res << ")";
		TempVar var = TempVar();
		if(func->id == "printi")
			CodeBuffer::instance().emit("call void @printi(i32 " + ((ExpList*)$3)->vars[0] + ")");
		else if(func->id == "print")
			CodeBuffer::instance().emit("call void @print(i8* " + ((ExpList*)$3)->vars[0] + ")");
		else if(func->return_type != "VOID"){//to add dont forget  + function_args///////////////////////////////////////////////////////////////////////
			CodeBuffer::instance().emit(var.name + " = call " + stack_symbol.update(func->return_type) + " @" + func->id + res.str());
			if(func->return_type == "BOOL"){
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = zext i1 " + var.name + " to i32");
			}else if(func->return_type == "BYTE"){								
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = zext i8 " + var.name + " to i32");
			}else {
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = add i32 " + var.name + ", 0");
			}
		}else{
			CodeBuffer::instance().emit("call " + stack_symbol.update(func->return_type) + " @" + func->id + res.str());
			}
	}
		| ID LPAREN RPAREN
	{
			if(!(stack_symbol.symbol_tables_contains_function(((Id*)$1)->str))){
		      errorUndefFunc(yylineno,((Id*)$1)->str );
			 exit(0);
			}
		Param* func = stack_symbol.get_function(((Id*)$1)->str);
		if(func->argument.size() != 0){
			errorPrototypeMismatch(yylineno, ((Id*)$1)->str, func->argument);
			exit(0);
		}
		$$= new Expression(func->return_type);
		if(func->return_type == "VOID")
			CodeBuffer::instance().emit("call " + stack_symbol.update(func->return_type) + " @" + func->id + "()");
		else{ 
			TempVar var = TempVar();
			CodeBuffer::instance().emit(var.name + " = call " + stack_symbol.update(func->return_type) + " @" + func->id + "()");
			if(func->return_type == "BOOL"){
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = zext i1 " + var.name + " to i32");
			}else if(func->return_type == "BYTE"){
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = zext i8 " + var.name + " to i32");
			}else {
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = add i32 " + var.name + ", 0");
			}
		}
	};
ExpList: Exp
	{
		$$= new ExpList();
		((ExpList*)$$)->types.push_back(((Expression*)$1)->type);
		((ExpList*)$$)->argument_frame_size += 4;
		if(((Expression*)$1)->type == "BOOL"){
			TempVar var = TempVar();
			string falseLabel = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().emit("store i1 0, i1* %bool");
			int loc1 = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc1,FIRST);
			vector<LabelPair> back_patch = CodeBuffer::instance().makelist(temp);
			string trueLabel = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().emit("store i1 1, i1* %bool");
			int loc2 = CodeBuffer::instance().emit("br label @");
			LabelPair temp1 (loc2,FIRST);
			vector<LabelPair> back_patch1 = CodeBuffer::instance().makelist(temp1);
			string next = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().emit(var.name + " = load i1, i1* %bool, align 4");
			((ExpList*)$$)->vars.push_back(var.name);
			CodeBuffer::instance().bpatch(((Expression*)$1)->true_list, trueLabel);
			CodeBuffer::instance().bpatch(((Expression*)$1)->false_list, falseLabel);
			CodeBuffer::instance().bpatch(back_patch, next);
			CodeBuffer::instance().bpatch(back_patch1, next);
		}
		else 
			((ExpList*)$$)->vars.push_back(((Expression*)$1)->place.name);
	} 
		| Exp{
					if(((Expression*)$1)->type == "BOOL"){
					TempVar var = TempVar();
					string falseLabel = CodeBuffer::instance().genLabel();
					CodeBuffer::instance().emit("store i1 0, i1* %bool");
					int loc1 = CodeBuffer::instance().emit("br label @");
					LabelPair temp (loc1,FIRST);
					vector<LabelPair> back_patch = CodeBuffer::instance().makelist(temp);
					string trueLabel = CodeBuffer::instance().genLabel();
					CodeBuffer::instance().emit("store i1 1, i1* %bool");
					int loc2 = CodeBuffer::instance().emit("br label @");
					LabelPair temp1 (loc2,FIRST);
					vector<LabelPair> back_patch1 = CodeBuffer::instance().makelist(temp1);
					string next = CodeBuffer::instance().genLabel();
					CodeBuffer::instance().emit(var.name + " = load i1, i1* %bool, align 4");
					((ExpList*)$$)->vars.push_back(var.name);
					CodeBuffer::instance().bpatch(((Expression*)$1)->true_list, trueLabel);
					CodeBuffer::instance().bpatch(((Expression*)$1)->false_list, falseLabel);
					CodeBuffer::instance().bpatch(back_patch, next);
					CodeBuffer::instance().bpatch(back_patch1, next);
				} 
			} 
		COMMA ExpList{
						$$ = $4;
						if(((Expression*)$1)->type != "BOOL")
							((ExpList*)$$)->vars.push_back(((Expression*)$1)->place.name);
						((ExpList*)$$)->types.push_back(((Expression*)$1)->type);
						((ExpList*)$$)->argument_frame_size += 4;
					};
Type: INT {$$ = new Node();
			$$->type = "INT";}
	| BYTE {$$ = new Node();
			$$->type = "BYTE";}
	| BOOL {$$ = new Node(); 
	    $$->type = "BOOL";
	}/*choose class */ ;
	
Exp: LPAREN Exp RPAREN { $$ = $2;}
    | Exp BINOP Exp {
					if((((Expression*)$1)->type != "INT" && ((Expression*)$1)->type !="BYTE") ||
						(((Expression*)$3)->type != "INT" && ((Expression*)$3)->type !="BYTE"))
					{
						output::errorMismatch(yylineno);
						exit(0);
					}
					if((((Expression*)$1)->type == "INT" && ((Expression*)$3)->type =="BYTE") ||
						(((Expression*)$3)->type == "INT" && ((Expression*)$1)->type =="BYTE"))
							$$ = new Expression("INT");
					else
						$$ = new Expression(((Expression*)$1)->type); 
					TempVar var1 = ((Expression*)$1)->place;
					TempVar var2 = ((Expression*)$3)->place;
					string op = ((Node*)$2)->str;
					TempVar temp = TempVar();
					if (op == "+") 
						CodeBuffer::instance().emit(temp.name + " = add i32 " + var1.name + ", " + var2.name);
					 else
							CodeBuffer::instance().emit(temp.name + " = sub i32 " + var1.name + ", " + var2.name);
					
					if (((Expression*)$$)->type == "BYTE") {
						TempVar temp2 = TempVar();
						CodeBuffer::instance().emit(temp2.name + " = trunc i32 " + temp.name + " to i8");
						CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = zext i8 " + temp2.name + " to i32");
					}
					else 
						CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = add i32 " + temp.name + ", 0");
		}
	| Exp MULTOP Exp 
					{
						if((((Expression*)$1)->type !="INT"&& ((Expression*)$1)->type != "BYTE") || 
						(((Expression*)$3)->type !="INT"&& ((Expression*)$3)->type != "BYTE"))
						{
							errorMismatch(yylineno);
							exit(0);
						}
						$$ = new Expression(((Expression*)$1)->type);
						if(((Expression*)$3)->type =="INT")
						{
							((Expression*)$$)->type = ((Expression*)$3)->type;
						}
						TempVar var1 = ((Expression*)$1)->place;
						TempVar var2 = ((Expression*)$3)->place;
						string op = ((Node*)$2)->str;
						TempVar temp1 = TempVar();
						if (op == "*") {
							CodeBuffer::instance().emit(temp1.name + " = mul i32 " + var1.name + ", " + var2.name);
						} else{
							TempVar var = TempVar();
							CodeBuffer::instance().emit(var.name + " = icmp eq i32 0, " + var2.name);
							CodeBuffer::instance().emit("br i1 " + var.name + ",label %label_div_by_zero" + ((Expression*)$$)->place.name + ", label %label_after" + ((Expression*)$$)->place.name);
							CodeBuffer::instance().emit("label_div_by_zero" + ((Expression*)$$)->place.name + ":");
							CodeBuffer::instance().emit("call void @print(i8* getelementptr inbounds ([23 x i8], [23 x i8]* @.zeroErr, i32 0, i32 0))");
							CodeBuffer::instance().emit("call void @exit(i32 0)");
							CodeBuffer::instance().emit("br label %label_after" + ((Expression*)$$)->place.name);
							CodeBuffer::instance().emit("label_after" + ((Expression*)$$)->place.name + ":");
							CodeBuffer::instance().emit(temp1.name + " = sdiv i32" + var1.name + ", " + var2.name);
						} 
						if (((Expression*)$$)->type == "BYTE") {
							TempVar temp2 = TempVar();
							CodeBuffer::instance().emit(temp2.name + " = trunc i32 " + temp1.name + " to i8");
							CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = zext i8 " + temp2.name + " to i32");
						}
						else 
							CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = add i32 " + temp1.name + ", 0");
					}
	| ID
		{
			Param* id_p = stack_symbol.get_param(((Id*)$1)->str);
			bool is_param=false;
			string type= "";
			int offset;
			if(!id_p){
				errorUndef(yylineno, ((Id*)$1)->str);
				exit(0);
			}
			if(stack_symbol.symbol_tables_contains_function(((Id*)$1)->str)){
				errorMismatch(yylineno);
				exit(0);
			}
			is_param=true;
			type=id_p->type;
			offset = (id_p->offset);
			$$ = new Expression(type, ((Id*)$1)->str,is_param);
			if (((Expression*)$$)->type != "VOID" && ((Expression*)$$)->type != "STRING") {
				TempVar var= TempVar();
				if(offset >= 0)
					CodeBuffer::instance().emit(var.name + " = getelementptr [50 x i32],[50 x i32]* %MyStack, i32 0, i32 "+ to_string(offset));
				else {
					offset = 0 - offset - 1;	
					CodeBuffer::instance().emit(var.name + " = getelementptr [50 x i32],[50 x i32]* %args, i32 0, i32 "+ to_string(offset));
				}
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = load i32, i32* " + var.name + ", align 4");
				if (((Expression*)$$)->type == "BOOL") {
					TempVar var1 = TempVar();
					CodeBuffer::instance().emit(var1.name + " = icmp eq i32 0, " + ((Expression*)$$)->place.name);
					int loc1 = CodeBuffer::instance().emit("br i1 " + var1.name + ", label @, label %label_next_to_call_1" + to_string(((Expression*)$$)->place.var_id));
					CodeBuffer::instance().emit("label_next_to_call_1" + to_string(((Expression*)$$)->place.var_id) + ":");
					LabelPair temp2 (loc1,FIRST);
					((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp2);
					int loc2 = CodeBuffer::instance().emit("br label @");
					LabelPair temp1 (loc2,FIRST);
					((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp1);
				}
			}
		}
	| Call 
		{ 
			if (((Expression*)$1)->type == "BOOL") {
				TempVar var = TempVar();
				CodeBuffer::instance().emit(var.name + " = icmp eq i32 0, " + ((Expression*)$1)->place.name);
				int loc1 = CodeBuffer::instance().emit("br i1 " + var.name + ", label @, label %label_next_to_call" + ((Expression*)$$)->place.name);
				CodeBuffer::instance().emit("label_next_to_call" + ((Expression*)$$)->place.name +  ":");
				LabelPair temp (loc1,FIRST);
				((Expression*)$1)->false_list = CodeBuffer::instance().makelist(temp);
				int loc2 = CodeBuffer::instance().emit("br label @");
				LabelPair temp1 (loc2,FIRST);
				((Expression*)$1)->true_list = CodeBuffer::instance().makelist(temp1);
			}
			$$ = $1;
		}
	| NUM  { $$ = new Expression("INT", ((Num*)$1)->str);
			CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = add i32 0, " + to_string(((Num*)$1)->val));
		   }
	| NUM B {	if( ((Num*)$1)->val > 255){
					errorByteTooLarge(yylineno, ((Num*)$1)->str);
					exit(0);
				} 
			$$ = new Expression("BYTE", ((Num*)$1)->str);
			CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = add i32 0, " + to_string(((Num*)$1)->val));
			}
	| STRING { $$= new Expression("STRING", ((String*)$1)->str);
	    	    newLable lable = newLable();
				int size = ((Expression*)$1)->str.size();
				stringstream res;
				for(int i = 1; i < size-1; ++i) {
					res << ((Expression*)$1)->str[i];
				}
				CodeBuffer::instance().emitGlobal(lable.name() + " = constant [" + to_string(size-1) + " x i8] c\"" + res.str() + "\\00\"");
				CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = getelementptr [" + to_string(size-1) + " x i8],[" + to_string(size-1) + " x i8]* " +lable.name() + ", i32 0, i32 0");
			 }
	| TRUE   { $$= new Expression("BOOL", "true");
				int loc1 = CodeBuffer::instance().emit("br label @");
				LabelPair temp (loc1,FIRST);
				((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp);
				((Expression*)$$)->false_list = vector<LabelPair>();
			 }
	| FALSE  { $$= new Expression("BOOL", "false");
				int loc1 = CodeBuffer::instance().emit("br label @");
				LabelPair temp (loc1,FIRST);
				((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp);
				((Expression*)$$)->true_list = vector<LabelPair>();
			 }
	| NOT Exp { if(((Expression*)$2)->type != "BOOL"){
	            errorMismatch(yylineno);
			    exit(0); 
	          }
	          $$ = $2;
			  vector<LabelPair> tmp = ((Expression*)$$)->true_list;
				((Expression*)$$)->true_list = ((Expression*)$$)->false_list;
				((Expression*)$$)->false_list = tmp;
			  }
	| Exp AND M Exp { 
				CodeBuffer::instance().bpatch(((Expression*)$1)->true_list, ((Node*)$3)->str);
				if(((Expression*)$1)->type != "BOOL" || ((Expression*)$4)->type != "BOOL"){
					errorMismatch(yylineno);
					exit(0);
				}
				$$ = new Expression("BOOL", ((Expression*)$1)->str);
				((Expression*)$$)->true_list = ((Expression*)$4)->true_list;
				((Expression*)$$)->false_list = CodeBuffer::instance().merge(((Expression*)$1)->false_list, ((Expression*)$4)->false_list);
	          }
	| Exp OR M Exp { 
				CodeBuffer::instance().bpatch(((Expression*)$1)->false_list, ((Node*)$3)->str);
				if(((Expression*)$1)->type != "BOOL" || ((Expression*)$4)->type != "BOOL")
				{
					errorMismatch(yylineno);
					exit(0);
				}
				$$ = new Expression("BOOL", ((Expression*)$1)->str);
				((Expression*)$$)->true_list = CodeBuffer::instance().merge(((Expression*)$1)->true_list, ((Expression*)$4)->true_list);
				((Expression*)$$)->false_list = ((Expression*)$4)->false_list;
	         }
	| Exp RELOP1 Exp{ 
				if((((Expression*)$1)->type != "BYTE" && ((Expression*)$1)->type != "INT") ||
				(((Expression*)$3)->type != "BYTE" && ((Expression*)$3)->type != "INT"))
				{
					errorMismatch(yylineno);
					exit(0);
				}
				$$ = new Expression("BOOL", ((Expression*)$1)->str);
				TempVar var = TempVar();
				string op = ((Node*)$2)->str;
				if (op == ">="){
					CodeBuffer::instance().emit(var.name + " = icmp sge i32 " + ((Expression*)$1)->place.name + ", " + ((Expression*)$3)->place.name);
					int loc1 = CodeBuffer::instance().emit("br i1 " + var.name + ", label @, label @");
					LabelPair temp_true (loc1,FIRST);
					LabelPair temp_false (loc1,SECOND);
					((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp_true);
					((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp_false);
				}else if(op == "<="){
					CodeBuffer::instance().emit(var.name + " = icmp sle i32 " + ((Expression*)$1)->place.name + ", " + ((Expression*)$3)->place.name);
					int loc1 = CodeBuffer::instance().emit("br i1 " + var.name + ", label @, label @");
					LabelPair temp_true (loc1,FIRST);
					LabelPair temp_false (loc1,SECOND);
					((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp_true);
					((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp_false);
				}else if(op == "<"){
					CodeBuffer::instance().emit(var.name + " = icmp slt i32 " + ((Expression*)$1)->place.name + ", " + ((Expression*)$3)->place.name);
					int loc1 = CodeBuffer::instance().emit("br i1 " + var.name + ", label @, label @");
					LabelPair temp_true (loc1,FIRST);
					LabelPair temp_false (loc1,SECOND);
					((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp_true);
					((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp_false);
				}else  if(op == ">"){
					CodeBuffer::instance().emit(var.name + " = icmp sgt i32 " + ((Expression*)$1)->place.name + ", " + ((Expression*)$3)->place.name);
					int loc1 = CodeBuffer::instance().emit("br i1 " + var.name + ", label @, label @");
					LabelPair temp_true (loc1,FIRST);
					LabelPair temp_false (loc1,SECOND);
					((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp_true);
					((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp_false);
				}
	      }
	| Exp RELOP2 Exp{ 
				if((((Expression*)$1)->type != "BYTE" && ((Expression*)$1)->type != "INT") ||
					(((Expression*)$3)->type != "BYTE" && ((Expression*)$3)->type != "INT"))
				{
					errorMismatch(yylineno);
					exit(0);
				}
				$$ = new Expression("BOOL", ((Expression*)$1)->str);
				TempVar var = TempVar();
				string op = ((Node*)$2)->str;
				if (op == "==") {
					CodeBuffer::instance().emit(var.name + " = icmp eq i32 " + ((Expression*)$1)->place.name + ", " + ((Expression*)$3)->place.name);
					int loc1 = CodeBuffer::instance().emit("br i1 " + var.name + ", label @, label @");
					LabelPair temp_true (loc1,FIRST);
					LabelPair temp_false (loc1,SECOND);
					((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp_true);
					((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp_false);
				}else if (op == "!=") {
					CodeBuffer::instance().emit(var.name + " = icmp ne i32 " + ((Expression*)$1)->place.name + ", " + ((Expression*)$3)->place.name);
					int loc1 = CodeBuffer::instance().emit("br i1 " + var.name + ", label @, label @");
					LabelPair temp_true (loc1,FIRST);
					LabelPair temp_false (loc1,SECOND);
					((Expression*)$$)->true_list = CodeBuffer::instance().makelist(temp_true);
					((Expression*)$$)->false_list = CodeBuffer::instance().makelist(temp_false);
				} 
		
	            }
	| LPAREN Type RPAREN Exp{
		if(((Expression*)$4)->type == "INT" || ((Expression*)$4)->type == "BYTE" || ((Expression*)$4)->type == "STRING" || 
			((Expression*)$4)->type == "BOOL" || ((Expression*)$4)->type == "VOID"){
				errorMismatch(yylineno);
				exit(0); 
		}
					$$ = new Expression("INT", ((Expression*)$4)->str);
					CodeBuffer::instance().emit(((Expression*)$$)->place.name + " = add i32 0, " + ((Expression*)$4)->place.name);
				}

M:	{
			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> bp = CodeBuffer::instance().makelist(temp);
			$$= new Node;
			((Node*)$$)->str = CodeBuffer::instance().genLabel();
			CodeBuffer::instance().bpatch(bp, ((Node*)$$)->str);
			
	};
N:{ //skip code to next label
			$$= new MarkerN();
			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			((MarkerN*)$$)->nextList = CodeBuffer::instance().makelist(temp);
	};

%%
void yyerror(const char* err){
	errorSyn(yylineno);
	exit(0);
}

int main(){
	return yyparse();
}
