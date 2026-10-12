#include <expat.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int count = 0;
static void start(void* ud, const XML_Char* name, const XML_Char** atts) { count++; }

int main() {
    XML_Parser p = XML_ParserCreate(NULL);
    XML_SetElementHandler(p, start, NULL);
    const char* doc = "<a><b/><c x=\"1\"/></a>"; // expat>=2.6 rejects len<0, pass explicit length
    assert(XML_Parse(p, doc, (int)strlen(doc), 1) == XML_STATUS_OK);
    assert(count == 3);
    printf("expat ok: %d elements\n", count);
    return 0;
}
