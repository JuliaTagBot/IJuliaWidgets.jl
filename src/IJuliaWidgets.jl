require("React")
require("Interact")

module IJuliaWidgets

using JSON
using React
using Interact

export mimewritable, writemime

if !isdefined(Main, :IJulia)
    error("IJuliaWidgets must be imported from inside an IJulia notebook")
end
    
const ijulia_js  = readall(joinpath(dirname(Base.source_path()), "ijulia.js"))

try
    display("text/html", """<script charset="utf-8">$(ijulia_js)</script>""")
catch
end

import IJulia
import IJulia: metadata, display_dict
using  IJulia.CommManager
import IJulia.CommManager: register_comm, comm_id
import Base: writemime, mimewritable

const comms = Dict{Signal, Comm}()

function send_update(comm :: Comm, v)
    # do this better!!
    # Thoughts:
    #    Queue upto 3, buffer others
    #    Diff and send
    #    Is display_dict the right thing?
    msg = Main.IJulia.display_dict(v)
    send_comm(comm, ["value" => msg])
end


display_dict(x :: Signal) =
    display_dict(x.value)

function metadata(x :: Signal)
    if !haskey(comms, x)
        # One Comm channel per signal object
        comm = Comm(:Signal)

        comms[x] = comm   # Backend -> Comm
        # prevent resending the first time?
        lift(v -> send_update(comm, v), x)
    else
        comm = comms[x]
    end
    return ["reactive"=>true,
            "comm_id"=>string(comm_id(comm))]
end

# Render the value of a signal.
mimewritable(io :: IO, m :: MIME, s :: Signal) =
    mimewritable(m, s.value)


writemime(io:: IO, m :: MIME, s :: Signal) =
    writemime(io, m, s.value)

writemime(io::IO, ::MIME{symbol("text/html")},
          w::InputWidget) =
              create_view(w)

## This is for our own widgets.
function register_comm{comm_id}(comm :: Comm{:InputWidget, comm_id}, msg)
    w_id = msg.content["data"]["widget_id"]
    w = get_widget(w_id)

    function CommManager.on_msg(::Comm{:InputWidget, symbol(comm_id)}, msg)
        v =  msg.content["data"]["value"]
        recv(w, v)
    end
end

JSON.print(io::IO, s::Signal) = JSON.print(io, s.value)

##################### IPython IPEP 23: Backbone.js Widgets #################

## AccordionView W
## ButtonView ✓
## CheckboxView ✓
## ContainerView W
## DropdownView ✓
## FloatSliderView ✓
## FloatTextView ✓
## HTMLView W
## ImageView W
## IntSliderView ✓
## IntTextView ✓
## LatexView W
## PopupView W
## ProgressView
## RadioButtonsView ✓
## SelectView ✓
## TabView W
## TextareaView ✓
## TextView ✓
## ToggleButtonsView
## ToggleButtonView ✓

# catchall view name for widgets
view_name(w::InputWidget) = string(typeof(w).name, "View")
view_name{T<:Integer}(::Slider{T}) = "IntSliderView"
view_name{T<:FloatingPoint}(::Slider{T}) = "FloatSliderView"
view_name{T<:Integer}(::Textbox{T}) = "IntTextView"
view_name{T<:FloatingPoint}(::Textbox{T}) = "FloatTextView"
view_name(::Textbox) = "TextView"
view_name{view}(::Options{view}) = string(view, "View")

function metadata(x :: Signal{InputWidget})
    lift(update_view, x)
    Dict()
end

function update_view(comm::Comm, w::InputWidget)
    msg = Dict()
    msg["method"] = "update"
    state = Dict()
    state["msg_throttle"] = 3
    state["_view_name"] = view_name(w)
    state["description"] = w.label
    state["visible"] = true
    state["disabled"] = false
    msg["state"] = merge(state, statedict(w))
    send_comm(comm, msg)
end

function create_view(w :: InputWidget)
    comm = Comm(:WidgetModel)

    # Send a full state update message.
    update_view(comm, w)
    send_comm(comm, ["method"=>"display"])

    # dispatch messages to widget's handler
    function CommManager.on_msg(::Comm{:WidgetModel, comm_id(comm)}, msg)
        handle_msg(w, msg)
        # finally notify the frontend of any changes
        update_view(comm, w)
    end
    nothing # display() nothing
end


include("statedict.jl")
include("handle_msg.jl")

end
