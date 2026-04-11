# Debiconf
Zprovoznění desktopového prostředí bez bloatwaru na čistém Debianu

Debian 13.4.0

AMD64: http://debian-cd.mirror.web4u.cz/13.4.0/amd64/iso-cd/debian-13.4.0-amd64-netinst.iso

ARM64: http://debian-cd.mirror.web4u.cz/13.4.0/arm64/iso-cd/debian-13.4.0-arm64-netinst.iso

--------------------------------------------------

Po dokončení čisté netinst instalace bez prostředí:

  su -
  
  apt install git -y
  
  git clone https://github.com/David96cz/debiconf
  
  cd debiconf
  
  bash debiconf.sh
