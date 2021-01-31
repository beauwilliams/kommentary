--[[--
Functions for commenting code in and out.

This module contains the functions for commenting lines/ranges
in/out/toggeling and detecting comments.
@module kommentary.kommentary
]]
local config = require("kommentary.config")
local util = require("kommentary.util")
local M = {}

--[[--
Check if a string is a single-line comment.
@tparam string line A single line string
@tparam string comment_string The prefix of a single-line comment
@treturn bool true if it is a single-line comment, otherwise false
]]
function M.is_comment_single(line, comment_string)
    -- Since the line might be indented, trim all whitespace
    line = util.trim(line)
    return line:sub(1, #comment_string) == comment_string
end

--[[--
Check if a string is a multi-line comment.
@tparam {string,...} lines A table of lines
@tparam {string,string} comment_strings A tuple containing the prefix and
        suffix of a multi-line comment
@treturn bool true if it is a multi-line comment, otherwise false
]]
function M.is_comment_multi(lines, comment_strings)
    if comment_strings == false then
        return false
    end
    -- Only the first and last lines are relevant, these may be the same
    local first_line = util.trim(lines[1])
    local last_line = util.trim(lines[#lines])
    local begins = first_line:sub(1, #comment_strings[1]) == comment_strings[1]
    local ends = last_line:sub(-#comment_strings[2]) == comment_strings[2]
    return begins and ends
end

--[[--
Check if a string is a range of single-line comments.
@tparam {string,...} lines A table of lines
@tparam string comment_string The prefix of a single-line comment
@treturn bool true if it is a range of single-line comments
]]
function M.is_comment_multi_single(lines, comment_string)
    for _, line in ipairs(lines) do
        if not M.is_comment_single(line, comment_string) then
            return false
        end
    end
    -- All of the lines are single-line comments
    return true
end

--[[--
Checks if the specified range in the buffer is a comment.
@tparam int line_number_start Start of the range, inclusive
@tparam int line_number_end End of the range, inclusive
@treturn bool true if it is a multi-line comment, otherwise false
]]
function M.is_comment(line_number_start, line_number_end)
    line_number_start = line_number_start-1
    -- Get the content of the range specififed, this will return a table of lines
    local content = vim.api.nvim_buf_get_lines(0, line_number_start, line_number_end, false)
    -- Check whether the range is a single- or multiline range, get the appropriate comment_string
    if #content == 1 then
        local comment_string = config.get_single(0)
        if not comment_string == false then
            return M.is_comment_single(content[1], comment_string)
        else
            -- In case the language doesn't support single-line comments
            comment_string = config.get_multi(0)
            return M.is_comment_multi(content, comment_string)
        end
    elseif #content > 1 then
        local comment_string = config.get_multi(0)
        local result = M.is_comment_multi(content, comment_string)
        -- If the language doesn't support multiline comments, or
        -- if the lines are not a multiline comment,
        -- they might still be multiple single-line comments
        if result then
            return result
        else
            comment_string = config.get_single(0)
            if comment_string == false then
                return result
            else
                return M.is_comment_multi_single(content, comment_string)
            end
        end
    else
        error("Empty range.")
    end
end

--[[--
Turns the line into a single-line comment.
@tparam int line_number Line to operate on
@tparam string comment_string The prefix of a single-line comment
@treturn nil
]]
function M.comment_in_line(line_number, comment_string)
    local content = vim.api.nvim_buf_get_lines(0, line_number-1, line_number, false)[1]
    vim.api.nvim_buf_set_lines(0, line_number-1, line_number, false, {util.insert_at_beginning(content, comment_string .. " ")})
end

--[[--
Turns the line, a single-line comment, into normal code.
This might not turn the line into normal code, if the line has been commented out
multiple times, for example in lua: `-- -- This has been commented out 2 times`,
in which case it will remove one *level* of comments, so in this example it will
turn into:  `-- This has been commented out 2 times`.
@tparam int line_number Line to operate on
@tparam string comment_string The prefix of a single-line comment
@treturn nil
]]
function M.comment_out_line(line_number, comment_string)
    local content = vim.api.nvim_buf_get_lines(0, line_number-1, line_number, false)[1]
    if M.is_comment_single(content, comment_string) then
        local result, _ = string.gsub(content, util.escape_pattern(comment_string) .. "%s*", "", 1)
        vim.api.nvim_buf_set_lines(0, line_number-1, line_number, false, {result})
    end
end

--[[--
Turns the range into multiple single-line comments.
@tparam int line_number_start Start of the range, inclusive
@tparam int line_number_end End of the range, inclusive
@treturn nil
]]
function M.comment_in_range_single(line_number_start, line_number_end)
    line_number_start = line_number_start-1
    for line_number = line_number_start+1, line_number_end, 1 do
        M.comment_in_line(line_number, config.get_single(0))
    end
end

--[[--
Turns the range into a multi-line comment.
If the language doesn't support multi-line comments, it will turn the range
into multiple single-line comments instead.
@tparam int line_number_start Start of the range, inclusive
@tparam int line_number_end End of the range, inclusive
@tparam {string,string} comment_string A tuple containing the prefix and
        suffix of a multi-line comment
@treturn nil
]]
function M.comment_in_range(line_number_start, line_number_end, comment_string)
    line_number_start = line_number_start-1
    local content = vim.api.nvim_buf_get_lines(0, line_number_start, line_number_end, false)
    if comment_string == false then
        -- The language doesn't support multi-line comments, just loop over
        -- each line and comment it in with a single-line comment
        M.comment_in_range_single(line_number_start, line_number_end)
    else
        local result = {}
        if line_number_start == line_number_end then
            result = {util.insert_at_beginning(content, comment_string[1] .. " ") .. " " .. comment_string[2]}
        else
            result = {}
            for i, line in ipairs(content) do
                if i == 1 then
                    result[i] = util.insert_at_beginning(line, comment_string[1] .. " ")
                else
                    result[i] = line
                end
            end
            result[#result] = result[#result] .. " " .. comment_string[2]
        end
        vim.api.nvim_buf_set_lines(0, line_number_start, line_number_end, false, result)
    end
end

--[[--
Turns the range, a multi-line comment, into normal code.
If the language doesn't support multi-line comments, it will comment out each
single line comment individually.
Just as with commenting out a single line, this might not make the range into
normal code, but remove one *level* of commenting instead.
@tparam int line_number_start Start of the range, inclusive
@tparam int line_number_end End of the range, inclusive
@tparam {string,string} comment_string A tuple containing the prefix and
        suffix of a multi-line comment
@treturn nil
@see comment_out_line
]]
function M.comment_out_range(line_number_start, line_number_end, comment_string)
    line_number_start = line_number_start-1
    local content = vim.api.nvim_buf_get_lines(0, line_number_start, line_number_end, false)
    -- If the range consists of multiple single-line comments
    local single_comments_array = comment_string == false
    if not comment_string == false then
        if M.is_comment_multi(content, comment_string) then
            local result = {}
            for i, line in ipairs(content) do
                local new_line = line
                if i == 1 then
                    new_line, _ = string.gsub(new_line, util.escape_pattern(comment_string[1]) .. "%s*", "", 1)
                end
                if i == #content then
                    -- This will make sure that only the last occurence of the suffix is replaced
                    local start_index = util.index_last_occurence(line, comment_string[2])
                    new_line, _ = util.gsub_from_index(new_line, "%s*" .. util.escape_pattern(comment_string[2]), "", 1, start_index)
                end
                result[i] = new_line
            end
            vim.api.nvim_buf_set_lines(0, line_number_start, line_number_end, false, result)
        else
            single_comments_array = true
        end
    end
    if single_comments_array then
        -- The language doesn't support multi-line comments, or the
        -- range just doesn't use them, either way: loop over each
        -- line and comment it out with a single-line comment
        for line_number = line_number_start+1, line_number_end, 1 do
            M.comment_out_line(line_number, config.get_single(0))
        end
    end
end

--[[--
Toggles commenting on the line.
This function will automatically resolve the proper comment_string for the
current buffer.
If the line is commented out multiple times, it will first remove all starting
comments before starting to toggle comments, so for example in lua:
`-- -- -- Test` would first become `-- -- Test`, then  `-- Test`, then finally
`Test` and from then on alternate between that and `-- Test`.
@tparam int line_number Line to operate on
@treturn nil
]]
function M.toggle_comment_line(line_number)
    local comment_string = config.get_single(0)
    -- If the language doesn't support single-line comments
    if comment_string == false then
        M.toggle_comment_range(line_number, line_number, true)
        return nil
    end
    if M.is_comment(line_number, line_number) then
        M.comment_out_line(line_number, comment_string)
    else
        M.comment_in_line(line_number, comment_string)
    end
end

--[[--
Toggles commenting on the range.
Behaves the same way as toggeling a single line.
@tparam int line_number_start Start of the range, inclusive
@tparam int line_number_end End of the range, inclusive
@tparam bool force_multi Force the use of multi-line comment prefix and suffix
@treturn nil
@see toggle_comment_line
]]
function M.toggle_comment_range(line_number_start, line_number_end, force_multi)
    --[[ If you start a selection and then move up, it would be detected
    as a negative range, so if that's the case swap the start and end. ]]
    if line_number_end < line_number_start then
        line_number_start, line_number_end = line_number_end, line_number_start
    end
    local comment_strings = config.get_multi(0)
    if M.is_comment(line_number_start, line_number_end) then
        M.comment_out_range(line_number_start, line_number_end, comment_strings)
    else
        --[[ If the range is a single line, do a single-line comment toggle instead,
        but only if trying to comment in since it could be annoying otherwise. ]]
        if line_number_end == line_number_start and not force_multi then
            M.toggle_comment_line(line_number_start)
            return nil
        end
        M.comment_in_range(line_number_start, line_number_end, comment_strings)
    end
end

return M
