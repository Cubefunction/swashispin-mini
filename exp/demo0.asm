.program dc16
.repeat 10
   ; swp v1=0 v2=5 n=20 dt=10us (arm)
   lvl v=4 t=50us (arm)
   lvl v=3 t=50us
   lvl v=2 t=50us (v+0.2)
   lvl v=1 t=50us
   lvl v=0 t=50us

.program dc17
.repeat 10
    ; swp v1=0 v2=-5 n=20 dt=10us (arm)
   lvl v=-4 t=50us (arm)
   lvl v=-3 t=50us
   lvl v=-2 t=50us (v+0.2)
   lvl v=-1 t=50us
   lvl v=0 t=50us

.program dc18
.repeat 10
    ; swp v1=-5 v2=5 n=20 dt=10us (arm)
    lvl v=3 t=50us (arm)
    lvl v=1 t=50us
    lvl v=-1 t=50us (v+0.2)
    lvl v=-3 t=50us
    lvl v=-5 t=50us

.program dc19
.repeat 10
    ; swp v1=5 v2=-5 n=20 dt=10us (arm)
    lvl v=-3 t=50us (arm)
    lvl v=-1 t=50us
    lvl v=1 t=50us (v+0.2)
    lvl v=3 t=50us
    lvl v=5 t=50us

.launch dc16 dc17 dc18 dc19

