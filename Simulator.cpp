#include "ComplianceTest.h"

int main(int argc, char *argv[])
{
    if (argc < 2)
        return -1;

    ComplianceTest test(argv[1]);
    test.run();

    return 0;
}
