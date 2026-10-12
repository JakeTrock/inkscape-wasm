#include <libxml/parser.h>
#include <libxslt/xslt.h>
#include <libxslt/transform.h>
#include <libxslt/xsltutils.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const char* STYLE =
    "<xsl:stylesheet version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform'>"
    "<xsl:template match='/'><out><xsl:value-of select=\"count(//*)\"/></out></xsl:template>"
    "</xsl:stylesheet>";

int main() {
    xsltInit();
    xmlDocPtr style = xmlReadMemory(STYLE, strlen(STYLE), NULL, NULL, 0);
    xsltStylesheetPtr ss = xsltParseStylesheetDoc(style);
    assert(ss);
    xmlDocPtr in = xmlReadFile("/fixtures/basic.svg", NULL, 0);
    xmlDocPtr out = xsltApplyStylesheet(ss, in, NULL);
    assert(out);
    xmlChar* txt = NULL; int len = 0;
    xsltSaveResultToString(&txt, &len, out, ss);
    assert(txt && strstr((char*)txt, "3")); // svg + 2 rects
    printf("libxslt ok: %.*s\n", len, (char*)txt);
    xmlFree(txt);
    xmlFreeDoc(out); xmlFreeDoc(in); xsltFreeStylesheet(ss);
    return 0;
}
