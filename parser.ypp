Statement: RestStatement {$$=$1;}
          |IF {stack_symbol.add_scope("if");}
		  LPAREN BoolExp RPAREN M Statement scopeClose
		  {
			CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, ((Node*)$5)->str);
			
			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> next_list = CodeBuffer::instance().makelist(temp);
			string next = CodeBuffer::instance().genLabel();
			
			CodeBuffer::instance().bpatch(((Expression*)$3)->false_list, next);
			
			CodeBuffer::instance().bpatch(next_list, next);
			$$ = $7;
		  }
	      |IF {stack_symbol.add_scope("if");}
		  LPAREN BoolExp RPAREN M Statement scopeClose 
		  N M ELSE {stack_symbol.add_scope("else");}
		  Statement scopeClose
		  {
			CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, ((Node*)$5)->str);
			CodeBuffer::instance().bpatch(((Expression*)$3)->false_list,((Node*)$10)->str);

			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> bp = CodeBuffer::instance().makelist(temp);
			string next = CodeBuffer::instance().genLabel();
			
			CodeBuffer::instance().bpatch(((MarkerN*)$9)->nextList, next);
			
			CodeBuffer::instance().bpatch(bp, next);
			$$ = $7;
			//((Stmnt*)$$)->breakList = CodeBuffer::instance().merge(((Stmnt*)$7)->breakList, ((Stmnt*)$13)->breakList);						
			//((Stmnt*)$$)->continueList = CodeBuffer::instance().merge(((Stmnt*)$7)->continueList, ((Stmnt*)$13)->continueList);
		  }
		  |WHILE {stack_symbol.add_scope("while");}
		  LPAREN BoolExp RPAREN M Statement scopeClose
		  {
			CodeBuffer::instance().bpatch(((Expression*)$3)->true_list, ((Node*)$5)->str);

			int loc = CodeBuffer::instance().emit("br label @");
			LabelPair temp (loc,FIRST);
			vector<LabelPair> next_list = CodeBuffer::instance().makelist(temp);
			string next = CodeBuffer::instance().genLabel();
			
			CodeBuffer::instance().bpatch(((Expression*)$3)->false_list, next);
			
			CodeBuffer::instance().bpatch(next_list, next);
			$$ = $7;
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
