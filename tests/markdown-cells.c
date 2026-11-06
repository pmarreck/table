/* Read the GFM renderer's HTML with libxml2, independently of the converter. */
#include <libxml/HTMLparser.h>
#include <libxml/tree.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void cells(xmlNode *node) {
    for (; node; node = node->next) {
        if (node->type == XML_ELEMENT_NODE &&
            (!xmlStrcmp(node->name, BAD_CAST "th") || !xmlStrcmp(node->name, BAD_CAST "td"))) {
            xmlChar *text = xmlNodeGetContent(node);
            size_t length = text ? strlen((const char *)text) : 0;
            printf("F%zu:", length);
            if (length) fwrite(text, 1, length, stdout);
            xmlFree(text);
        } else cells(node->children);
    }
}
int main(void) {
    size_t length = 0, capacity = 4096;
    char *input = malloc(capacity);
    if (!input) return 1;
    for (;;) {
        if (length == capacity) {
            if (capacity > 0x3fffffff) { free(input); return 1; }
            capacity *= 2;
            char *next = realloc(input, capacity);
            if (!next) { free(input); return 1; }
            input = next;
        }
        size_t count = fread(input + length, 1, capacity - length, stdin);
        length += count;
        if (!count) break;
    }
    if (ferror(stdin) || length > 0x7fffffff) { free(input); return 1; }
    htmlDocPtr document = htmlReadMemory(input, (int)length, NULL, "UTF-8", HTML_PARSE_NONET | HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING);
    free(input);
    if (!document) return 1;
    cells(xmlDocGetRootElement(document));
    xmlFreeDoc(document);
    return fflush(stdout) || ferror(stdout) ? 1 : 0;
}
