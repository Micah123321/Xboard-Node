package gfwcheck

func DefaultTargets() map[string][]Target {
	return map[string][]Target{
		"ct": {
			{Name: "北京电信", Host: "v4-bj-ct.oojj.de"},
			{Name: "上海电信", Host: "61.170.82.99"},
			{Name: "江苏电信", Host: "v4-js-ct.oojj.de"},
			{Name: "广东电信", Host: "gd-ct-v4.ip.zstaticcdn.com"},
			{Name: "四川电信", Host: "sc-ct-v4.ip.zstaticcdn.com"},
			{Name: "重庆电信", Host: "cq-ct-v4.ip.zstaticcdn.com"},
		},
		"cu": {
			{Name: "北京联通", Host: "v4-bj-cu.oojj.de"},
			{Name: "上海联通", Host: "sh-cu-v4.ip.zstaticcdn.com"},
			{Name: "江苏联通", Host: "js-cu-v4.ip.zstaticcdn.com"},
			{Name: "广东联通", Host: "gd-cu-v4.ip.zstaticcdn.com"},
			{Name: "云南联通", Host: "14.205.93.189"},
			{Name: "重庆联通", Host: "cq-cu-v4.ip.zstaticcdn.com"},
		},
		"cm": {
			{Name: "北京移动", Host: "bj-cm-v4.ip.zstaticcdn.com"},
			{Name: "上海移动", Host: "sh-cm-v4.ip.zstaticcdn.com"},
			{Name: "山东移动", Host: "218.201.96.130"},
			{Name: "广东移动", Host: "211.136.192.6"},
			{Name: "四川移动", Host: "183.221.253.100"},
			{Name: "重庆移动", Host: "cq-cm-v4.ip.zstaticcdn.com"},
		},
	}
}
