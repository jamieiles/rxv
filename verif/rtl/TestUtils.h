#pragma once
#include <fcntl.h>
#include <unistd.h>
#include <boost/format.hpp>

#include <gtest/gtest.h>

static inline std::string current_test_name()
{
    auto test_info = ::testing::UnitTest::GetInstance()->current_test_info();
    return (boost::format("%s.%s") % test_info->test_case_name() %
            test_info->name())
        .str();
}

class OutputSuprocessor
{
public:
    OutputSuprocessor(int fd) : oldfd(fd)
    {
        savedfd = dup(fd);

        int new_fd = open("/dev/null", O_WRONLY);
        dup2(new_fd, fd);
    }

    ~OutputSuprocessor()
    {
        close(oldfd);
        dup2(savedfd, oldfd);
    }

private:
    int oldfd;
    int savedfd;
};