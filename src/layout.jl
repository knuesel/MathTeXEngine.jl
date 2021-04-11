
"""
    tex_layout(mathexpr::TeXExpr, fontset)

Recursively determine the layout of the math expression represented the given
TeXExpr for the given font set.

Currently the only supported font set is NewComputerModern.
"""
function tex_layout(expr, fontset=NewComputerModern)
    head = expr.head
    args = [expr.args...]
    n = length(args)
    shrink = 0.6

    if head == :group
        elements = tex_layout.(args, Ref(fontset))
        return horizontal_layout(elements)
    elseif head == :decorated
        core, sub, super = tex_layout.(args, Ref(fontset))

        core_width = advance(core)
        sub_width = advance(sub) * shrink
        super_width = advance(super) * shrink

        return Group(
            [core, sub, super],
            Point2f0[
                (0, 0),
                (core_width, -0.2),
                (core_width, xheight(core) - 0.5 * descender(super))],
            [1, shrink, shrink])
    elseif head == :integral
        pad = 0.2
        sub, super = tex_layout.(args[2:3], Ref(fontset))

        # TODO Generalize this to other symbols ? This should be decided by the
        # fontset
        topint = get_symbol_char('⌠', raw"\inttop", fontset)
        botint = get_symbol_char('⌡', raw"\intbottom", fontset)

        top = Group([topint, super],
            Point2f0[
                (0, 0),
                (inkwidth(topint) + pad, topinkbound(topint) - xheight(super))
            ],
            [1, shrink])
        bottom = Group([botint, sub],
            Point2f0[
                (0, 0),
                (inkwidth(botint) + pad, bottominkbound(botint))
            ],
            [1, shrink])

        return Group(
            [top, bottom],
            Point2f0[
                (leftinkbound(topint), xheight(fontset.math)/2),
                (leftinkbound(botint), xheight(fontset.math)/2 - inkheight(botint) - bottominkbound(botint))
            ],
            [1, 1]
            )
    elseif head == :underover
        core, sub, super = tex_layout.(args, Ref(fontset))

        mid = hmid(core)
        dxsub = mid - hmid(sub) * shrink
        dxsuper = mid - hmid(super) * shrink

        under_offset = bottominkbound(core) - (ascender(sub) - xheight(sub)/2) * shrink
        over_offset = topinkbound(core) - descender(super)

        # The leftmost element must have x = 0
        x0 = -min(0, dxsub, dxsuper)

        return Group(
            [core, sub, super],
            Point2f0[
                (x0, 0),
                (x0 + dxsub, under_offset),
                (x0 + dxsuper, over_offset)
            ],
            [1, shrink, shrink]
        )
    elseif head == :function
        name = args[1]
        elements = get_function_char.(collect(name), Ref(fontset))
        return horizontal_layout(elements)
    elseif head == :space
        return Space(args[1])
    elseif head == :spaced_symbol
        char, command = args[1].args
        sym = get_symbol_char(char, command, fontset)
        return horizontal_layout([Space(0.2), sym, Space(0.2)])
    elseif head == :delimited
        # TODO Parsing of this is crippling slow and I don't know why
        elements = tex_layout.(args, Ref(fontset))
        left, content, right = elements

        height = inkheight(content)
        left_scale = max(1, height / inkheight(left))
        right_scale = max(1, height / inkheight(right))
        scales = [left_scale, 1, right_scale]
            
        dxs = advance.(elements) .* scales
        xs = [0, cumsum(dxs[1:end-1])...]

        # TODO Height calculation for the parenthesis looks wrong
        # TODO Check what the algorithm should be there
        # Center the delimiters in the middle of the bot and top baselines ?
        return Group(elements, 
            Point2f0[
                (xs[1], -bottominkbound(left) + bottominkbound(content)),
                (xs[2], 0),
                (xs[3], -bottominkbound(right) + bottominkbound(content))
        ], scales)
    elseif head == :accent || head == :wide_accent
        # TODO
    elseif head == :font
        # TODO
    elseif head == :frac
        numerator = tex_layout(args[1], fontset)
        denominator = tex_layout(args[2], fontset)

        # extend fraction line by half an xheight
        xh = xheight(fontset.math)
        w = max(inkwidth(numerator), inkwidth(denominator)) + xh/2

        # fixed width fraction line
        lw = thickness(fontset)

        line = HLine(w, lw)
        y0 = xh/2 - lw/2

        # horizontal center align for numerator and denominator
        x1 = (w-inkwidth(numerator))/2
        x2 = (w-inkwidth(denominator))/2

        ytop    = y0 + xh/2 - bottominkbound(numerator)
        ybottom = y0 - xh/2 - topinkbound(denominator)

        return Group(
            [line, numerator, denominator],
            Point2f0[(0,y0), (x1, ytop), (x2, ybottom)],
            [1,1,1]
            )
    elseif head == :sqrt
        content = tex_layout(args[1], fontset)
        sqrt = get_symbol_char('√', raw"\sqrt", fontset)

        thick = thickness(fontset)
        relpad = 0.15

        h = inkheight(content)
        ypad = relpad * h
        h += 2ypad

        if h > inkheight(sqrt)
            sqrt = get_symbol_char('⎷', raw"\sqrtbottom", fontset)
        end

        h = max(inkheight(sqrt), h)

        # The root symbol must be manually placed
        y0 = bottominkbound(content) - bottominkbound(sqrt) - ypad/2
        y = y0 + bottominkbound(sqrt) + h
        xpad = advance(sqrt) - inkwidth(sqrt)
        w =  inkwidth(content) + 2xpad

        lw = sqrt_thickness(fontset)
        hline = HLine(w, lw)
        vline = VLine(inkheight(sqrt) - h, lw)

        return Group(
            [sqrt, hline, vline, content],
            Point2f0[
                (0, y0),
                (inkwidth(sqrt) - lw/2, y - lw/2),
                (inkwidth(sqrt) - lw/2, y),
                (advance(sqrt), 0)],
            [1, 1, 1, 1])
    elseif head == :symbol
        char, command = args
        return get_symbol_char(char, command, fontset)
    end

    @error "Unsupported expr $expr"
end

tex_layout(char::TeXChar, fontset) = char
tex_layout(::Nothing, fontset) = Space(0)
tex_layout(char::Char, fontset) = get_math_char(char, fontset)

function tex_layout(integer::Integer, fontset)
    elements = get_number_char.(collect(string(integer)), Ref(fontset))
    return horizontal_layout(elements)
end

function horizontal_layout(elements ; scales=ones(length(elements)))
    dxs = advance.(elements)
    xs = [0, cumsum(dxs[1:end-1])...]

    return Group(elements, Point2f0.(xs, 0), scales)
end

"""
    unravel(element::TeXElement, pos, scale)

Flatten the layouted TeXElement and produce a single list of base element with
their associated absolute position and scale.
"""
function unravel(group::Group, parent_pos=Point2f0(0), parent_scale=1.0f0)
    positions = [parent_pos .+ pos for pos in parent_scale .* group.positions]
    scales = group.scales .* parent_scale
    elements = []

    for (elem, pos, scale) in zip(group.elements, positions, scales)
        push!(elements, unravel(elem, pos, scale)...)
    end

    return elements
end

unravel(char::ScaledChar, pos, scale) = unravel(char.char, pos, scale*char.scale)
unravel(element, pos, scale) = [(element, pos, scale)]
