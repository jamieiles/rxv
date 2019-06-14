#include "ComplianceTest.h"

int main(int argc, char *argv[])
{
    if (argc < 2)
        return -1;

    ComplianceTest test(argv[1]);

    return test.run() ? 0 : 1;
}
