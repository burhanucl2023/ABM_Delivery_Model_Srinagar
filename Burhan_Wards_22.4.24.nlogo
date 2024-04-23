extensions[gis]                  ;; GIS Extension for Netlogo

breed [points point]             ;; Nodes for Navigation
breed [couriers courier]         ;; Courier Delivery Persons

globals [
  srinagar-road                  ;; GIS Dataset for Major Roads of my hometown "Srinagar"
  srinagar-boundary              ;; GIS Dataset for City boundary layer & includes all the wards of Srinagar city
  reached-destination            ;; Count of Deliveries Completed
  profit-loss                    ;; Net Profit or Loss (if value is positive so that means profit and if negative that means loss)
  profit-loss-percentage         ;; Percentage of profit or loss relative to total revenue from deliveries
  ;charges-per-delivery          ;; It is the income generated from each delivery
  ;salary-cost-percentage        ;; It is the percentage of income spent on courier-driver salary per delivery
  ;operational-cost-percentage   ;; It is the percentage of income spent on operational cost such as commuting charges, etc per delivery -
                                 ;; so it depends on no. of nodes to reach the delivery point.
  ;other-expenses-percentage     ;; It is the percentage of income spent on other administrative expenses per delivery
  ]

patches-own[
  ward-centroid?                 ;; Ward Centriod
  id                             ;; Unique identifier for each ward i.e. each ward has an different "id"
  road_entry                     ;; Nearest Road point to Ward Centroid
]

couriers-own [
   current_vertex                ;; Starting Road point where the Courier Agent (Delivery Person) starts
   target_patch                  ;; Target Road point for Delivery completion
   target_ward_entry             ;; Nearest road point to ward centroid for delivery
   route_plan                    ;; Sequence of nodes forming the shortest path to the target_patch
   path_step_counter             ;; Index of the current node in the path i.e. the number of steps to reach the target_patch (stores number of nodes traversed)
   last-stop                     ;; Most recent delivery location
   deliveries-made               ;; Total number of deliveries made by the courier

   current-delivery-distance     ;; Distance traveled in the current delivery

   salary-cost-per-delivery      ;; Salary cost attributed to each delivery i.e. Cost per delivery based on courier-driver salary
   operational-cost-per-node     ;; Operational cost per node visited i.e. Cost per node for operational expenses
   other-expenses                ;; Other miscellaneous expenses per delivery
]

points-own [
  near_points                    ;; Neighboring points connected to this point
  entry_gate?                    ;; Indicates if the point serves as an entry to ward
  temp
  distance_origin                ;; used in path finding algorithm
  complete                       ;; Indicates if shortest path calculation is complete for this point (1 or 0)
  previous_node                  ;; Previous node in the shortest path to this point
  ]

to setup
  ca
  reset-ticks
  reading_gis_data
  generate-ward-centroids
  generate-road-data
  remove_excess_nodes                                   ;; only one node in same patch considered
  ask points [set near_points link-neighbors]
  remove_isolated_nodes                                 ;; removing nodes not in the network
  ask points [set near_points link-neighbors]
  generate-entrances                                    ;; entrance to wards
  generate-couriers                                     ;; courier delivery persons setup
  set profit-loss 0                                     ;; Initialize finances
  ask links [set thickness 0.075 set color red]
end
                                                        ;; reading the gis data - wards, road data
to reading_gis_data
  set srinagar-boundary gis:load-dataset "data/Burhan_data/Srinagar.shp"
  set srinagar-road gis:load-dataset "data/Burhan_data/Roads_Test.shp"
  gis:set-world-envelope gis:envelope-of srinagar-boundary
  gis:set-drawing-color blue
  gis:draw srinagar-boundary 1.5

end
                                                        ;; generating the ward centroids
to generate-ward-centroids
  foreach gis:feature-list-of srinagar-boundary [
    feature ->
    let c gis:location-of gis:centroid-of feature
    ask patch item 0 c item 1 c [
      set ward-centroid? true
      set id gis:property-value feature "Id"
    ]
  ]
end
                                                         ;; generating road data by creating links between the nodes
to generate-road-data
  foreach gis:feature-list-of srinagar-road [
    road-feature ->
    foreach gis:vertex-lists-of road-feature [
      v ->
      let prev_point nobody
      foreach v [
        node ->
        let location gis:location-of node
        if not empty? location [
          create-points 1 [
            set near_points n-of 0 turtles ;; Empty
            set xcor item 0 location
            set ycor item 1 location
            set size 0.20
            set shape "square"
            set color green
            set hidden? false
            ifelse prev_point = nobody [
            ] [
              create-link-with prev_point
            ]
            set prev_point self
          ]
        ]
      ]
    ]
  ]
end
                                                            ;; generating entrance to wards by assigning nearest road node/point to ward
to generate-entrances
   ask patches with [ward-centroid? = true][
    set road_entry min-one-of points in-radius 50 [distance myself]
    ask road_entry [
      set entry_gate? true
      set hidden? false
      set shape "target"
      set size 0.5
    ]
  ]
end
                                                             ;; generating couriers and assigning different variables to the commuters
to generate-couriers
  create-couriers number-of-couriers [
    set color yellow
    set size 0.5
    set shape "person"
    set target_patch nobody
    set last-stop nobody
    set current_vertex one-of points move-to current_vertex
    set deliveries-made 0
    set current-delivery-distance 0
    set salary-cost-per-delivery ((salary-cost-percentage / 100) * charges-per-delivery)
    set operational-cost-per-node ((operational-cost-percentage / 100) * charges-per-delivery)
    set other-expenses ((other-expenses-percentage / 100) * charges-per-delivery)
  ]
  set reached-destination 0
end

                                                             ;; go setup (what happens with each tick)
to go
  ask couriers [
    ifelse target_patch = nobody [
      ; Set up the target_patch if not set up
      setup-destination
    ][
      ; Proceed with the path if the target_patch is set
      ifelse xcor != [xcor] of target_ward_entry or ycor != [ycor] of target_ward_entry [
        ; Continue moving towards target_patch if not arrived
        follow-path
      ][
        complete-delivery
      ]
    ]
  ]
  tick
end
                                                             ;; assigning destination to the couriers randomly out of the wards available
to setup-destination
  set target_patch one-of patches with [ward-centroid? = true]
  set target_ward_entry [road_entry] of target_patch
  while [target_ward_entry = current_vertex] [
    set target_patch one-of patches with [ward-centroid? = true]
    set target_ward_entry [road_entry] of target_patch
  ]
  route_search
end
                                                             ;; movement of the courier from point to point
to follow-path
  if path_step_counter < length route_plan [
    let next-node item path_step_counter route_plan
    move-to next-node
    increment-delivery-distance next-node
    set path_step_counter path_step_counter + 1
  ]
end
                                                             ;; delivery completion as well as variable updation
to complete-delivery
  set profit-loss profit-loss +
    (charges-per-delivery) -
    (salary-cost-per-delivery) -
    (operational-cost-per-node * path_step_counter) -
    (other-expenses)
  ;; Increment the count of successful deliveries
  set reached-destination reached-destination + 1
  ;; Update the profit loss percentage after incrementing reached-destination
  update-profit-loss-percentage  ;; Update the profit loss percentage here
  set last-stop target_patch
  set target_patch nobody
  set deliveries-made deliveries-made + 1
  set path_step_counter 0  ; Reset for the next delivery
  set route_plan []  ; Clear the path for the next delivery
end


to increment-delivery-distance [next-node]
  let prev-node current_vertex
  move-to next-node
  set current_vertex next-node
end
                                                              ;; to remove excess nodes within each patch, for simplification & ease of computation
to remove_excess_nodes
  ask points [
    if count points-here > 1[
      ask other points-here [
        ask myself [
          create-links-with other [link-neighbors] of myself
        ]
        die
      ]
    ]
  ]

end
                                                              ;; to remove isolated nodes
to remove_isolated_nodes
  ask points [set temp 0]
  ask one-of points [set temp 1]
  repeat 500 [
    ask points with [temp = 1] [
      ask near_points [
        set temp 1
      ]
    ]
  ]
  ask points with [temp = 0][die]
end
                                                               ;; path finding algorithm
to route_search
  set route_plan []
  set path_step_counter 0
  ask points [
    set distance_origin 99999  set complete 0  set previous_node nobody   set color green
  ]
  ask current_vertex [ set distance_origin 0 ]
  while [count points with [complete = 0] > 0] [
    ask points with [distance_origin < 99999 and complete = 0][
      ask near_points [
        let dist0 distance myself + [distance_origin] of myself
        if distance_origin > dist0 [
          set distance_origin dist0
          set complete 0
          set previous_node myself
        ]
      ]
      set complete 1
    ]
  ]
  let x target_ward_entry
  while [x != current_vertex] [
    ask x [set color white]
    set route_plan fput x route_plan
    set x [previous_node] of x
  ]
end
                                                               ;; compute average deliveries per courier
to-report average-deliveries-per-courier
  ifelse count couriers > 0 [
    report sum [deliveries-made] of couriers / count couriers
  ][
    report 0
  ]
end
                                                               ;; update profit-loss percentage of the whole system
to update-profit-loss-percentage
  if reached-destination > 0 [
    set profit-loss-percentage (profit-loss / (charges-per-delivery * reached-destination)) * 100
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
276
10
921
656
-1
-1
27.7
1
10
1
1
1
0
0
0
1
-11
11
-11
11
0
0
1
ticks
30.0

BUTTON
107
10
170
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
52
142
224
175
number-of-couriers
number-of-couriers
1
100
1.0
1
1
NIL
HORIZONTAL

BUTTON
33
38
96
71
go
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
192
39
255
72
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1315
307
1490
356
Total Deliveries Made
reached-destination
1
1
12

TEXTBOX
44
484
194
502
NIL
10
0.0
1

MONITOR
943
311
1119
360
Average Deliveries
average-deliveries-per-courier
2
1
12

PLOT
1082
19
1490
234
Profit/Loss Percentage Over Time
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Profit/Loss Percentage" 1.0 0 -13345367 true "" "plot profit-loss-percentage"

SLIDER
52
233
224
266
charges-per-delivery
charges-per-delivery
50
500
100.0
50
1
NIL
HORIZONTAL

SLIDER
55
402
227
435
salary-cost-percentage
salary-cost-percentage
10
50
10.0
10
1
NIL
HORIZONTAL

SLIDER
46
451
236
484
operational-cost-percentage
operational-cost-percentage
10
50
10.0
10
1
NIL
HORIZONTAL

SLIDER
51
502
238
535
other-expenses-percentage
other-expenses-percentage
2
20
10.0
2
1
NIL
HORIZONTAL

MONITOR
1032
389
1454
470
Net Profit / Loss (AMOUNT) - COMPANY
profit-loss
3
1
20

MONITOR
1043
500
1458
581
Net Profit / Loss (%age) - COMPANY 
profit-loss-percentage
2
1
20

TEXTBOX
75
309
225
394
Adjust the proportions of salary, operational costs, and other expenses relative to the Delivery Fee
14
15.0
0

TEXTBOX
76
81
226
132
 Select the Number \n    of Couriers \n(Delivery Persons)
14
104.0
1

TEXTBOX
85
202
235
220
Set Delivery Fee
14
53.0
1

TEXTBOX
940
87
1090
155
Gives the Dynamic Profit/Loss %age\nChart of Delivery Company over time
14
0.0
1

TEXTBOX
963
254
1113
305
   Gives Average Deliveries done by\nall the Courier Agents
14
0.0
1

TEXTBOX
1331
249
1481
300
    Gives Total \nDeliveries completed \nby all Courier Agents
14
0.0
1

TEXTBOX
1048
366
1467
384
Give Net Amount made by the Delivery Company (Profit/Loss)
14
0.0
1

TEXTBOX
1054
477
1465
495
Gives the Net Profit/Loss %age made by the Delivery Company
14
0.0
1

@#$#@#$#@
     Strategic Route Planning and Economic Analysis for Delivery Services:
      An Agent-Based Modelling Case Study of Srinagar City.


## WHAT IS IT?

This model simulates a delivery service operating in Srinagar, my hometown. It incorporates the city's actual ward boundaries and major road networks to create a realistic setting. By employing a pathfinding algorithm, the model efficiently determines the shortest route between two points. Additionally, it offers the ability to monitor financial outcomes, track the average and total deliveries made by couriers, and analyze overall performance. Agents in the model randomly select destinations within different wards and navigate these routes to complete deliveries.

## HOW IT WORKS

In the beginning, each agent (courier delivery person) randomly selects a ward as a destination point and then identify the shortest path to the destination. The path algorithm is used to find the shortest path in terms of distance. The couriers move one node in a tick. When they reach the destination, they stay there for one tick, and then find the next destination and move again.And, the model calculates the entire economics of the buisness. It keeps track of deliveries, the Profit/Loss Values and Profit/Loss Percentages and provides the same via the Monitors & Graph Available in the Interface Window.

## Simulation Setup Instructions

 1. **Courier Delivery Personnel Creation:**
   Use the *number-of-couriers* slider to set the desired number of courier delivery persons. This controls how many couriers will be active in the simulation.

 2. **Charges Per Delivery**
   Adjust the *charges-per-delivery* slider to define the amount that the courier company charges for each delivery.

 3. **Salary Expenses:**
   The *salary-cost-percentage* slider determines what fraction of the delivery charges goes towards the courier's salary per delivery. The formula used is:


	- *Salary Expenses per delivery = (salary-cost-percentage) * (charges-per-delivery)*

 4. **Operational Costs:**
   Use the *operational-cost-percentage* slider to set the percentage of the delivery charge that is allocated to operational costs per node traversed by the courier.
The cost for each delivery, based on the number of nodes (steps) taken to reach the destination, is calculated as follows:


	- *Operational Cost per Node = (operational-cost-percentage) * (charges-per-delivery)*
	- *Operational Cost per Delivery = Operational Cost per Node Traversed * (path_step_counter)*

 5. **Other Expenses:**
   The *other-expenses-percentage* slider allows us to specify the fraction of the delivery charges that covers other administrative expenses per delivery:


	- *Other Expenses per delivery = (other-expenses-percentage) * (charges-per-delivery)*

 6. **Run the Simulation:**
   Press the *go* button to start or continue the simulation. This controls the movement of couriers as they make deliveries.

 7. **Path Visualization:**
   For detailed tracking, the nodes light up to "yellow" after the path is obtained for the courier by the path finding algorithm.


## EXTENDING THE MODEL

- Each courier delivery person could be assigned to specific wards only and he would carry delivery in those wards only, to reduce Operational Costs as well as Delivery Time to the Customers ?

- Some wards should be have more deliveries, so more courier delivery persons could be assigned to those wards, meaning the distribution of courier delivery persons would be unequal in the city, so as to cater to maximum demand?

## NETLOGO FEATURES

- The model incorporates financial variables that reflect the real-world dynamics of a delivery business.
- A pathfinding algorithm is utilized to ensure smooth and rapid model execution. The network data has been optimized by simplifying the number of nodes and removing duplicates on the same patch. (The way of creating the road network by using links is inpired by the Reston commuters model by Melanie Swartz)

## RELATED MODELS

Reston commuters model by Melanie Swartz

## CREDITS AND REFERENCES

The way of creating the road network by using links is inpired by the Reston commuters model by Melanie Swartz.

Model created by Burhan Ahmad Wani as part of Final Project Coursework for Module (CASA0011: Agent-based Modelling for Spatial Systems 23/24) at University College London (UCL).
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
