#include <libxml/parser.h>
#include <libxml/xpath.h>
#include <assert.h>
#include <stdio.h>

int main() {
    xmlDocPtr doc = xmlReadFile("/fixtures/basic.svg", NULL, 0);
    assert(doc);
    xmlXPathContextPtr ctx = xmlXPathNewContext(doc);
    assert(ctx);
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(BAD_CAST "//*[local-name()='rect']", ctx);
    assert(obj && obj->nodesetval && obj->nodesetval->nodeNr == 2);
    printf("libxml2 ok: %d rects found\n", obj->nodesetval->nodeNr);
    xmlXPathFreeObject(obj);
    xmlXPathFreeContext(ctx);
    xmlFreeDoc(doc);
    return 0;
}
