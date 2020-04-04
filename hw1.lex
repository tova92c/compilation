%{
/* Declarations section */ 
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int showToken(const char * name);
int hexToDec(const char* hex);
int binToDec(const char* bin);
int octToDec(const char* oct);
int power(int a, int b);
int commentToNum(const char* cmt);
int line_num = 1;
%} 

%option yylineno
%option noyywrap
%x comment
%x str

digit [0-9]
real {digit}\.{digit}*|{digit}*\.{digit}
letter [a-zA-Z]
whitespace [\r\t\n ]
relop ((==)|(!=)|(<=)|(>=)|(<)|(>))
logop [(&&)(||)]
binop [%+*/-]
%%



"Int"|"UInt"|"Double"|"Float"|"Bool"|"String"|"Character"	return showToken("TYPE");
"var" return showToken("VAR");
"let" return showToken("LET");
"func" return showToken("FUNC");
"import" 	 return showToken("IMPORT");
"nil" return showToken("NIL");
"true" return showToken("TRUE");
"false" return showToken("FALSE");
"->"	return showToken("ARROW");
":"	return showToken("COLON");
"return" return showToken("RETURN");
"if" return showToken("IF");
"else" return showToken("ELSE");
"while" return showToken("WHILE");
";" return showToken("SC");
"," return showToken("COMMA");
"(" return showToken("LPAREN");
")" return showToken("RPAREN");
"{" return showToken("LBRACE");
"}" return showToken("RBRACE");
"[" return showToken("LBRACKET");
"]" return showToken("RBRACKET");
"=" return showToken("ASSIGN");
{relop} return showToken("RELOP");
{logop} return showToken("LOGOP");
{binop} return showToken("BINOP");
{real}	return showToken("DEC_REAL");
{real}[Ee]["+""-"]{digit}	return showToken("DEC_REAL");
"0x"[a-zA-Z0-9]+[Pp]["+""-"][0-9]   return showToken("HEX_FP");
"0b"[0-1]+	 {sprintf(yytext, "%d", binToDec(yytext+2));return showToken("BIN_INT");}
"0o"[0-7]+	 {sprintf(yytext, "%d", octToDec(yytext+2));return showToken("OCT_INT");}
"0x"[a-zA-Z0-9]+	{sprintf(yytext, "%d", hexToDec(yytext+2));return showToken("HEX_INT");}
{digit}+	return showToken("DEC_INT");
{letter}[a-zA-Z0-9]*	return showToken("ID");
"_"[a-zA-Z0-9]+ return showToken("ID");

"/*"         BEGIN(comment);
<comment><<EOF>> {printf("Error unclosed comment\n");exit(0);}
<comment>[^*(\n|\r)]*"/*" 	{printf("Warning nested comment\n");exit(0);}
<comment>[^*(\n|\r)]*
<comment>[^*(\n|\r)]*(\n|\r)      ++line_num;
<comment>"*"+[^*/\n]*
<comment>"*"+[^*[/\n/\r]]*(\n|\r) ++line_num;
<comment>"*"+"/"        {sprintf(yytext, "%d", line_num);showToken("COMMENT");BEGIN(INITIAL);}

\/\/[^(\n\r|\n|\r)]* {yytext="1";return showToken("COMMENT");}


\"         BEGIN(str);  
<str>(\\.|[^\"\n\r])*\"        {showToken("STRING");BEGIN(INITIAL);}

{whitespace} ;
. printf("Error %s\n",yytext);exit(0);
%%

int showToken(const char* name){
	printf("%d %s %s\n",yylineno,name,yytext);
	return 1;
}

int hexToDec(const char* hex){
	int i  = strlen(hex)-1;
	int val =0, decimal = 0;
    for(; i>=0; --i) {
        if(hex[i]>='0' && hex[i]<='9')
            val = hex[i] - '0';
        else if(hex[i]>='a' && hex[i]<='f')
            val = hex[i] - 'a'+10;
        else if(hex[i]>='A' && hex[i]<='F')
            val = hex[i] - 'A' + 10;

        decimal += (val * power(16, i));
    }	
	return decimal;
}

int binToDec(const char* bin){
    int decimal = 0,base = 1; 
	int i = strlen(bin)- 1;
    for ( ;i >= 0; i--) { 
        if (bin[i] == '1') 
            decimal += base; 
        base = base * 2; 
    } 
    return decimal; 
}

int octToDec(const char* oct){
	int i  = strlen(oct)-1;
	int decimal = 0,val=0; 
    for ( ;i >= 0; --i) {
		if(oct[i]>='0' && oct[i]<='7')
			val = oct[i]-'0'; 
		 
		 decimal += val*power(8,i);
	}
	return decimal;
}

int power(int a, int b){
	int i=0,res=1;
	for(;i<b;++i)
		res*=a;
return res;
}

int commentToNum(const char* cmt){
	int count=1;
	while(cmt){
		if(*cmt=='\r'||*cmt=='\n')
			count++;
	}
return count;
}