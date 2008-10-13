#ifdef NEED_MINIMAL_NODE

#include "minimal_node.h"
#include <string.h>

int NODE_MEMO = 0;
int NODE_METHOD = 0;
int NODE_FBODY = 0;
int NODE_CFUNC = 0;
int NODE_CALL = 0;
int NODE_FCALL = 0;
int NODE_SPLAT = 0;
int NODE_LIT = 0;
int NODE_BLOCK_PASS = 0;

char const * ruby_node_name(int node);

static int node_value(char const * name)
{
  /* TODO: any way to end the block? */
  int j;
  for(j = 0; ; ++j)
  {
    if(!strcmp(name, ruby_node_name(j)))
    {
      return j;
    }
  }
}

void Init_ludicrous_minimal_node()
{
  NODE_MEMO = node_value("NODE_MEMO");
  NODE_METHOD = node_value("NODE_METHOD");
  NODE_FBODY = node_value("NODE_FBODY");
  NODE_CFUNC = node_value("NODE_CFUNC");
  NODE_CALL = node_value("NODE_CALL");
  NODE_FCALL = node_value("NODE_FCALL");
  NODE_SPLAT = node_value("NODE_SPLAT");
  NODE_LIT = node_value("NODE_LIT");
  NODE_BLOCK_PASS = node_value("NODE_BLOCK_PASS");
}

#endif

