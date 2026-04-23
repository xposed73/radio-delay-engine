#!/bin/bash
# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}📊 Radio Delay System Status${NC}"
echo "--------------------------------"

# Check Icecast
if systemctl is-active --quiet icecast2; then
    echo -e "Icecast2:      ${GREEN}RUNNING${NC}"
else
    echo -e "Icecast2:      ${RED}STOPPED${NC}"
fi

# Check Recorder
if systemctl is-active --quiet radio-recorder; then
    echo -e "Recorder:      ${GREEN}RUNNING${NC}"
else
    echo -e "Recorder:      ${RED}STOPPED${NC}"
fi

# Check Liquidsoap
if systemctl is-active --quiet radio-liquidsoap; then
    echo -e "Liquidsoap:    ${GREEN}RUNNING${NC}"
else
    echo -e "Liquidsoap:    ${RED}STOPPED${NC}"
fi

echo "--------------------------------"
echo -e "${BLUE}📂 Storage Status${NC}"
DU=$(du -sh /opt/radio-delay/recordings 2>/dev/null | cut -f1)
COUNT=$(ls /opt/radio-delay/recordings/*.mp3 2>/dev/null | wc -l)
echo "Recordings:    $COUNT files ($DU)"

echo "--------------------------------"
echo -e "${BLUE}🌐 Network (Public URLS)${NC}"
IP=$(curl -s ifconfig.me)
source /opt/radio-delay/config.env 2>/dev/null
echo "Icecast Admin: http://$IP:$ICECAST_PORT"
echo "Check logs with: journalctl -u radio-liquidsoap -n 50 --no-pager"
