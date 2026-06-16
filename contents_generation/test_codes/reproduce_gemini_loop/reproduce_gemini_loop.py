# reproduce_gemini_loop.py
import os, sys, json
from pathlib import Path
from dotenv import load_dotenv

# Ensure we can import from contents_generation
current_dir = Path(__file__).resolve().parent
sys.path.append(str(current_dir.parents[2]))
sys.path.append(str(current_dir.parents[2] / "contents_generation" / "scripts"))

from contents_generation.scripts.llm.llm_unified import UnifiedLLM, LLMOptions, Message

TOPIC = {
    'idx': 4,
    'title': 'RBAC, Direct Access & Covert Channels',
    'start_sid': 's000381',
    'end_sid': 's000545'
}

PARTIAL_TRANSCRIPT = [
    {'sid': 's000361', 'text': 'I should say that the UCLA Information Technology Group is not following this principle.', 'role': 'lecture'},
    {'sid': 's000362', 'text': "They're not telling you what they're doing.", 'role': 'lecture'},
    {'sid': 's000363', 'text': 'Right.', 'role': 'chitchat'},
    {'sid': 's000364', 'text': "In fact, if you're looking on the Net now for all of this stuff, all this stuff, in fact, they don't even tell me what they're doing.", 'role': 'lecture'},
    {'sid': 's000365', 'text': "And I've asked for like.", 'role': 'lecture'},
    {'sid': 's000366', 'text': "But if they were following this principle, then they would be letting all of us know what they're doing and what they're up to.", 'role': 'lecture'},
    {'sid': 's000367', 'text': "That's an important goal, and to some extent it's an idealized goal.", 'role': 'lecture'},
    {'sid': 's000368', 'text': "There's always the argument that if you have a system that's really good and really secure, then if you also keep your crypto algorithm and keep your.", 'role': 'lecture'},
    {'sid': 's000369', 'text': 'That will make it even more secure.', 'role': 'lecture'},
    {'sid': 's000370', 'text': 'Right.', 'role': 'chitchat'},
    {'sid': 's000371', 'text': "And there's validity to that argument.", 'role': 'lecture'},
    {'sid': 's000372', 'text': 'The problem though is that you just have to assume this stuff will leak out.', 'role': 'lecture'},
    {'sid': 's000373', 'text': 'The source code to Microsoft Windows is public now because somebody leaked it.', 'role': 'lecture'},
    {'sid': 's000374', 'text': 'Right.', 'role': 'chitchat'},
    {'sid': 's000375', 'text': "There's just not much you can do about that sort of thing.", 'role': 'lecture'},
    {'sid': 's000376', 'text': "So you really shouldn't assume that your procedures or algorithms are secret because in the end they probably won't.", 'role': 'lecture'},
    {'sid': 's000377', 'text': "That's the basic idea.", 'role': 'lecture'},
    {'sid': 's000378', 'text': "All right, so, oh my goodness, I've gone off into left field here.", 'role': 'lecture'},
    {'sid': 's000379', 'text': "I'm doing this lecture in a completely different order than what I have in my notes.", 'role': 'lecture'},
    {'sid': 's000380', 'text': "So I hope you don't mind if it seems a little bit disorganized.", 'role': 'lecture'},
    {'sid': 's000381', 'text': 'I was talking about access controls versus capabilities.', 'role': 'lecture'},
    {'sid': 's000382', 'text': 'And I was saying, okay, we need to have certain of a better way of thinking about things than having sort of a perimeter based access control versus something else.', 'role': 'lecture'},
    {'sid': 's000383', 'text': 'And in some sense zero trust architecture addresses that issue or at least tries to.', 'role': 'lecture'},
    {'sid': 's000384', 'text': "But I want to go back to the idea of access control and say, regardless of whether you used perimeter based or zero trust, there's something kind of wrong about the access control list stuff that I told you about last time and that something that's kind of wrong is something that's violating a principle that I wrote down somewhere.", 'role': 'lecture'},
    {'sid': 's000385', 'text': 'Not here.', 'role': 'lecture'},
    {'sid': 's000386', 'text': 'Where did I write it?', 'role': 'lecture'},
    {'sid': 's000387', 'text': 'Oh, yes, this one here.', 'role': 'lecture'},
    {'sid': 's000388', 'text': 'The principle of least privilege.', 'role': 'lecture'},
    {'sid': 's000389', 'text': "This thing which, which is a big deal either with DPA or with ddac, is something that the access control list stuff doesn't always work very well, so here I want to say I want to improve on ACLs.", 'role': 'lecture'},
    {'sid': 's000390', 'text': 'And the idea here is we want to use the principle of least privilege.', 'role': 'lecture'},
    {'sid': 's000391', 'text': "And here's the problem.", 'role': 'lecture'},
    {'sid': 's000392', 'text': 'When I log into CSNET, which uses ACL, I come in and authenticate myself as Dr. Eggert.', 'role': 'lecture'},
    {'sid': 's000393', 'text': "And because I'm Dr. Eggert, there's at least two things I can do that ordinary people can.", 'role': 'lecture'},
    {'sid': 's000394', 'text': 'One is I can install stuff in the user local cs.', 'role': 'lecture'},
    {'sid': 's000395', 'text': "They've given me access to that, Right?", 'role': 'lecture'},
    {'sid': 's000396', 'text': 'Right.', 'role': 'chitchat'},
    {'sid': 's000397', 'text': 'So I can access or write to shell settings User local.', 'role': 'lecture'},
    {'sid': 's000398', 'text': 'Another thing that I can do is I can go and look at the grading directory, right?', 'role': 'lecture'},
    {'sid': 's000399', 'text': 'Edit the gradient directory.', 'role': 'lecture'},
    {'sid': 's000400', 'text': "We don't tell you about the gradient directory.", 'role': 'lecture'},
    {'sid': 's000401', 'text': 'So I can change system software and I can grade.', 'role': 'lecture'},
    {'sid': 's000402', 'text': 'Those are two things that I have perfect right to do.', 'role': 'lecture'},
    {'sid': 's000403', 'text': "And that's why the ACL said, oh yeah, Dr.", 'role': 'lecture'},
    {'sid': 's000404', 'text': 'Ingredient can do it.', 'role': 'lecture'},
    {'sid': 's000405', 'text': "But now suppose I run a program that's designed to help me do grading better.", 'role': 'lecture'},
    {'sid': 's000406', 'text': "It's the Super Grader program.", 'role': 'lecture'},
    {'sid': 's000407', 'text': 'So I log in, I run the Super Grader program, it figures out what grades everybody should get.', 'role': 'lecture'},
    {'sid': 's000408', 'text': 'Saves me a lot of work.', 'role': 'lecture'},
    {'sid': 's000409', 'text': "I'm really happy.", 'role': 'lecture'},
    {'sid': 's000410', 'text': "The problem with ACLS is that Super Grader program can also like to use a local CS because I'm logged in as me and I have the ability to do both of these things.", 'role': 'lecture'},
    {'sid': 's000411', 'text': 'So when I run any program, that program also can do both of these things.', 'role': 'lecture'},
    {'sid': 's000412', 'text': "Even though that's violating the principle least privilege.", 'role': 'lecture'},
    {'sid': 's000413', 'text': "I'm giving to this Super Grader program the ability to do stuff in category number one.", 'role': 'lecture'},
    {'sid': 's000414', 'text': "I don't want to let it do that.", 'role': 'lecture'},
    {'sid': 's000415', 'text': "I only want to let it do stuff in number two because that's what it's supposed to be.", 'role': 'lecture'},
    {'sid': 's000416', 'text': "There is a technique that improves on ACL that will let me address this issue and it's called Role Based Access people.", 'role': 'lecture'},
    {'sid': 's000417', 'text': "It's not supported on Linux, but it is supported on some Linux like systems also.", 'role': 'lecture'},
    {'sid': 's000418', 'text': "It can be supported of course, if you have a web application where you're setting up your own access control mechanism.", 'role': 'lecture'},
    {'sid': 's000419', 'text': 'And in fact if you look at bruinlearn, Bruin Learn does use rgac because when I add people to a course on Bruin learning, one of the things that it asks me about is oh, what roles will this person play?', 'role': 'lecture'},
    {'sid': 's000420', 'text': "So with role based access control you don't look just at what, what we talked about last time, right?", 'role': 'lecture'},
    {'sid': 's000421', 'text': 'Principles.', 'role': 'lecture'},
    {'sid': 's000422', 'text': "And then we had objects and we had actions and there was a three dimensional array of bits that said this principle could do this action on this object that's ordinary access control, which ACLs deal with.", 'role': 'lecture'},
    {'sid': 's000423', 'text': 'With role based access control, we add one more thing.', 'role': 'lecture'},
    {'sid': 's000424', 'text': 'We have roles.', 'role': 'lecture'},
    {'sid': 's000425', 'text': "I'll put them here.", 'role': 'lecture'},
    {'sid': 's000426', 'text': 'And principles have roles.', 'role': 'lecture'},
    {'sid': 's000427', 'text': 'But these other things, the objects of the action, talk not only about what principles can do, it talks about what roles can do.', 'role': 'lecture'},
    {'sid': 's000428', 'text': 'So the idea is that someone who is operating in the role of software maintenance can do this.', 'role': 'lecture'},
    {'sid': 's000429', 'text': "Somebody who's operating the role of grading can do this.", 'role': 'lecture'},
    {'sid': 's000430', 'text': "But when I log in, I'll say, I don't have either of those roles.", 'role': 'lecture'},
    {'sid': 's000431', 'text': "If I want to do one of those other things, I will tell the operating system, okay, I'm going to put my grading hat on.", 'role': 'lecture'},
    {'sid': 's000432', 'text': 'So now I have this grading role and now I can do this stuff according to the grading role.', 'role': 'lecture'},
    {'sid': 's000433', 'text': "And then when I'm done, I'll take my grading hat off.", 'role': 'lecture'},
    {'sid': 's000434', 'text': 'Will lose those capabilities.', 'role': 'lecture'},
    {'sid': 's000435', 'text': "This will let me sort of be able to trust that the grading program can't do all the other things that I can do.", 'role': 'lecture'},
    {'sid': 's000436', 'text': 'It can only do the grading system.', 'role': 'lecture'},
    {'sid': 's000437', 'text': 'Any question about this technology?', 'role': 'qa'},
    {'sid': 's000438', 'text': 'Role based access.', 'role': 'lecture'},
    {'sid': 's000439', 'text': "So the upside of RBAC is it's more fine grained, it probably matches better how people actually operate.", 'role': 'lecture'},
    {'sid': 's000440', 'text': "And the downside, I hope you can see the downside is that it's one more thing to worry about.", 'role': 'lecture'},
    {'sid': 's000441', 'text': 'All of a sudden your configuration is going to get more complicated.', 'role': 'lecture'},
    {'sid': 's000442', 'text': 'People will have to understand this new thing.', 'role': 'lecture'},
    {'sid': 's000443', 'text': "What's a role?", 'role': 'lecture'},
    {'sid': 's000444', 'text': "I don't see it in my sum up, what is this thing?", 'role': 'lecture'},
    {'sid': 's000445', 'text': 'And so this extra complexity is going to make the system harder to maintain, harder to explain, harder to manage.', 'role': 'lecture'},
    {'sid': 's000446', 'text': "And that's one thing that you're going to have to worry about with R Vac.", 'role': 'lecture'},
    {'sid': 's000447', 'text': "All right, one more little thing while we're on the topic of security and implementation.", 'role': 'lecture'},
    {'sid': 's000448', 'text': "I've kind of talked about this before, but it's worth some of emphasizing it.", 'role': 'lecture'},
    {'sid': 's000449', 'text': 'So here we go, we get to emphasize it, which is direct versus indirect access.', 'role': 'lecture'},
    {'sid': 's000450', 'text': 'To resources.', 'role': 'lecture'},
    {'sid': 's000451', 'text': 'And in operating systems the usual distinction is as follows.', 'role': 'lecture'},
    {'sid': 's000452', 'text': "Direct access hands you a map directly into your address space, Which means now you can have a pointer into the object that you're looking at and you can access this object and perhaps update it if you're given write access very efficiently.", 'role': 'lecture'},
    {'sid': 's000453', 'text': 'Right?', 'role': 'chitchat'},
    {'sid': 's000454', 'text': "So, so here it's very efficient access, but that's a plus, a minus of this is going to be that the access check is only when you do the mapping, When the operating system makes the object visible to you and so you have a pointer into it.", 'role': 'lecture'},
    {'sid': 's000455', 'text': "When it's doing that, it can be suspicious.", 'role': 'lecture'},
    {'sid': 's000456', 'text': "I Don't want to have that access to the site.", 'role': 'lecture'},
    {'sid': 's000457', 'text': "But once it's giving you access, because the memory management hardware says, yes, Bob, I'll just do whatever you want, then from then on you can do sort of whatever you want.", 'role': 'lecture'},
    {'sid': 's000458', 'text': "So it's really fast, but in some sense it runs afoul of zta, right?", 'role': 'lecture'},
    {'sid': 's000459', 'text': 'Because if you had access five seconds ago, you still have access.', 'role': 'lecture'},
    {'sid': 's000460', 'text': 'And so another downside here is that the resource is more easily corrupted.', 'role': 'lecture'},
    {'sid': 's000461', 'text': 'If you have write access to the resource, you can modify it and maybe if the program is buggy or malevolent, you can modify it and screw up a more resource entirety.', 'role': 'lecture'},
    {'sid': 's000462', 'text': "So that's going to be a problem.", 'role': 'lecture'},
    {'sid': 's000463', 'text': 'Indirect access is going to be you issue service requests, You know, via system calls or handlers or.', 'role': 'lecture'},
    {'sid': 's000464', 'text': 'So a plus side of this, of course, is now you can do a check right on each axis.', 'role': 'lecture'},
    {'sid': 's000465', 'text': 'So this fits into the, you know, the ZTA approach a lot better than the other one does.', 'role': 'lecture'},
    {'sid': 's000466', 'text': 'Also, it means you can revoke axis.', 'role': 'lecture'},
    {'sid': 's000467', 'text': 'Because you check on each access.', 'role': 'lecture'},
    {'sid': 's000468', 'text': "If for some reason your permissions get removed, the next time you access, you can't access it anymore.", 'role': 'lecture'},
    {'sid': 's000469', 'text': "But of course the problem here is it's going to be slow.", 'role': 'lecture'},
    {'sid': 's000470', 'text': "If you're in a network environment, you're going to be kind of slow anyway.", 'role': 'lecture'},
    {'sid': 's000471', 'text': "So to some extent this Benny doesn't count.", 'role': 'lecture'},
    {'sid': 's000472', 'text': "But if you're in a local environment, the speed, speed is a big thing.", 'role': 'lecture'},
    {'sid': 's000473', 'text': 'People like to run fast.', 'role': 'lecture'},
    {'sid': 's000474', 'text': "They don't want their LLMs to be even smaller than they already are.", 'role': 'lecture'},
    {'sid': 's000475', 'text': 'So in a local model, you might want to do direct access rather than remote.', 'role': 'lecture'},
    {'sid': 's000476', 'text': "There's one other issue that I'd like to talk about before we take our break.", 'role': 'lecture'},
    {'sid': 's000477', 'text': "Many times in operating systems we like to say, here's a wall between two processes.", 'role': 'lecture'},
    {'sid': 's000478', 'text': "Here's process one.", 'role': 'lecture'},
    {'sid': 's000479', 'text': "Or maybe it's virtual machine one, here's process two, Virtual machine, right, whichever.", 'role': 'lecture'},
    {'sid': 's000480', 'text': "And this wall, unless we've arranged to put holes in it, maybe there's a pipe or something like that.", 'role': 'lecture'},
    {'sid': 's000481', 'text': "But assuming there's no sort of file that they can both access, there's no pipe communicating one process to the other, anything like that.", 'role': 'lecture'},
    {'sid': 's000482', 'text': 'This wall is supposed to be absolute.', 'role': 'lecture'},
    {'sid': 's000483', 'text': 'There should be no information leakage out of this guy into this guy.', 'role': 'lecture'},
    {'sid': 's000484', 'text': "If this guy has your password or has your secret key, this guy shouldn't have it.", 'role': 'lecture'},
    {'sid': 's000485', 'text': 'This sort of setup is very common and local operating systems all the time.', 'role': 'lecture'},
    {'sid': 's000486', 'text': 'When you run your browser, at least when I run my browser, each browser tab is running in a separate process.', 'role': 'lecture'},
    {'sid': 's000487', 'text': "And that's because in the past, Firefox and Chrome have both been so lucky.", 'role': 'lecture'},
    {'sid': 's000488', 'text': "They have these bad pointer bugs and the attackers are trying to break through from their website into somebody else's website.", 'role': 'lecture'},
    {'sid': 's000489', 'text': 'And they finally came out and miss it will run each tab in a separate process, then there will be no problems.', 'role': 'lecture'},
    {'sid': 's000490', 'text': 'Unfortunately, there can still be problems.', 'role': 'lecture'},
    {'sid': 's000491', 'text': 'And the basic sort of name for these problems in general is called covert channels.', 'role': 'lecture'},
    {'sid': 's000492', 'text': 'Covert channels exist when there is some code in here, in process one.', 'role': 'lecture'},
    {'sid': 's000493', 'text': 'That is in some sense molev.', 'role': 'lecture'},
    {'sid': 's000494', 'text': "It's trying to leak information that it knows because it has access to Virtual Machine 1 or processes one's memory.", 'role': 'lecture'},
    {'sid': 's000495', 'text': 'It wants to leak information encoded processes.', 'role': 'lecture'},
    {'sid': 's000496', 'text': "And it wants to do that even though there's this wall, there's no pipe, there's no file it can write to.", 'role': 'lecture'},
    {'sid': 's000497', 'text': "There's, you know, if you look at the formal security model for Linux, there's just no way it can talk to that other process.", 'role': 'lecture'},
    {'sid': 's000498', 'text': 'But yet it can.', 'role': 'lecture'},
    {'sid': 's000499', 'text': 'There is a way that the coding process too can find out oftentimes with the collaboration in the coding process, sometimes even without any help from the coding process.', 'role': 'lecture'},
    {'sid': 's000500', 'text': 'And this problem keeps a lot of security designers up at night.', 'role': 'lecture'},
    {'sid': 's000501', 'text': "It's a real problem.", 'role': 'lecture'},
    {'sid': 's000502', 'text': "They're constantly finding new ways to do covert channels.", 'role': 'lecture'},
    {'sid': 's000503', 'text': "I will give you one example of a covert channel that's really old fashioned and simple because I don't want to be accused of teaching you how to break a business.", 'role': 'lecture'},
    {'sid': 's000504', 'text': 'We know how to defend against this.', 'role': 'lecture'},
    {'sid': 's000505', 'text': "So here's the basic type of Suppose there's no five of any communication, but we still want to leak information.", 'role': 'lecture'},
    {'sid': 's000506', 'text': "And to keep things simple, let's assume we want to just leak one bit of information.", 'role': 'lecture'},
    {'sid': 's000507', 'text': 'Just one bit.', 'role': 'lecture'},
    {'sid': 's000508', 'text': 'Usually you want something longer.', 'role': 'lecture'},
    {'sid': 's000509', 'text': 'You want to leak an entire 2048bit key or something like that, but you do that one bit at a time.', 'role': 'lecture'},
    {'sid': 's000510', 'text': 'We want to send 1bito to all.', 'role': 'lecture'},
    {'sid': 's000511', 'text': "And here's how we do it.", 'role': 'lecture'},
    {'sid': 's000512', 'text': 'We say if the bit is true, then we say 4 I equals 0.', 'role': 'lecture'},
    {'sid': 's000513', 'text': 'PI is less than a zillion square plus plus do nothing.', 'role': 'lecture'},
    {'sid': 's000514', 'text': "Otherwise we'll do a sleep for a second, probably less than.", 'role': 'lecture'},
    {'sid': 's000515', 'text': 'So what are we doing here?', 'role': 'lecture'},
    {'sid': 's000516', 'text': "We're making our core busy.", 'role': 'lecture'},
    {'sid': 's000517', 'text': "If we want to set a one and we're making our core idle if we want to send a zero.", 'role': 'lecture'},
    {'sid': 's000518', 'text': 'What does this guy over here do?', 'role': 'lecture'},
    {'sid': 's000519', 'text': "This guy says, oh, what's the CPU temperature?", 'role': 'lecture'},
    {'sid': 's000520', 'text': "Which is something you can ask the operating system or it might ask, you know, what's the CQ time.", 'role': 'lecture'},
    {'sid': 's000521', 'text': 'Consumed?', 'role': 'lecture'},
    {'sid': 's000522', 'text': "Or it might just ask what's the time of day you know, one of a small set of purely innocent questions that you really want code to be able to do because you should be able to monitor how your program's running.", 'role': 'lecture'},
    {'sid': 's000523', 'text': 'But the thing is that the answer to one of these innocent questions can depend on what that is, right?', 'role': 'lecture'},
    {'sid': 's000524', 'text': "Because if this guy's really busy and chewing up CPU time, the CPU temperature goes up or maybe consumes more CPU time, and you can look at the accounting table or something like that.", 'role': 'lecture'},
    {'sid': 's000525', 'text': 'You can just do a PS on the process of trying to send you information, and it will tell you how much CPU time it takes.', 'role': 'lecture'},
    {'sid': 's000526', 'text': "There's all sorts of ways that you can communicate data covertly this way.", 'role': 'lecture'},
    {'sid': 's000527', 'text': "And the problem with covert channels is so severe, it's so hard to defend against that people have been trying for decades, that to some extent a lot of security designers today have given up.", 'role': 'lecture'},
    {'sid': 's000528', 'text': "They basically say we can't solve the COVID channel problem on local systems.", 'role': 'lecture'},
    {'sid': 's000529', 'text': 'We might be able to solve it on a network where we put each computation on a separate box.', 'role': 'lecture'},
    {'sid': 's000530', 'text': "But if you're just relying on VMs for security, if you're using AWS and you're renting a VM from Amazon, watch out, you could be a victim of this kind of attack.", 'role': 'lecture'},
    {'sid': 's000531', 'text': 'All right, any questions about covert channels or anything else?', 'role': 'qa'},
    {'sid': 's000532', 'text': 'Yes.', 'role': 'chitchat'},
    {'sid': 's000533', 'text': "Wouldn't this like require the two processes to like intentionally be trying to communicate?", 'role': 'qa'},
    {'sid': 's000534', 'text': 'Yes.', 'role': 'qa'},
    {'sid': 's000535', 'text': "I'm giving you an old, old example of sort of.", 'role': 'lecture'},
    {'sid': 's000536', 'text': 'I mean, this sort of attack is really easy to launch, right?', 'role': 'lecture'},
    {'sid': 's000537', 'text': 'But it requires cooperation.', 'role': 'lecture'},
    {'sid': 's000538', 'text': "There are cover channel attacks that don't require on cooperation, but they do require bugs in process.", 'role': 'lecture'},
    {'sid': 's000539', 'text': "So here's a classic.", 'role': 'lecture'},
    {'sid': 's000540', 'text': "Well, I probably shouldn't tell you all the details.", 'role': 'lecture'},
    {'sid': 's000541', 'text': "Here's a classic bug in process one, it checks your password and it uses a password checking algorithm that takes longer for long passes than for short one.", 'role': 'lecture'},
    {'sid': 's000542', 'text': 'So the sneaky process can from that make an inference about the length of your password.', 'role': 'lecture'},
    {'sid': 's000543', 'text': "So that would be one sort of Course, just knowing the length isn't enough.", 'role': 'lecture'},
    {'sid': 's000544', 'text': 'You have to know more stuff.', 'role': 'lecture'},
    {'sid': 's000545', 'text': 'But that flavor of attack can actually be used in some cases in poorly designed password algorithms to figure out what the entire password is.', 'role': 'lecture'},
    {'sid': 's000546', 'text': "Other Comments all right, let's take a break.", 'role': 'announcement'},
    {'sid': 's000547', 'text': "We'll start up again in about seven minutes.", 'role': 'announcement'},
    {'sid': 's000548', 'text': 'Up top up.', 'role': 'chitchat'},
    {'sid': 's000549', 'text': "Since we're an engineering school, we can finish up by talking about what can go wrong with security.", 'role': 'lecture'},
    {'sid': 's000550', 'text': "And fella, I've been mostly talking about defense.", 'role': 'lecture'},
    {'sid': 's000551', 'text': "Now to some extent, here's where the defense is.", 'role': 'lecture'},
    {'sid': 's000552', 'text': 'And security developers spend a lot of time thinking about failure modes more Than they perhaps.', 'role': 'lecture'},
    {'sid': 's000553', 'text': "In other words, areas of operating systems, there's two sort of major areas that you have to worry about.", 'role': 'lecture'},
    {'sid': 's000554', 'text': 'Well, more than two.', 'role': 'lecture'},
    {'sid': 's000555', 'text': "We'll start off with two.", 'role': 'lecture'},
    {'sid': 's000556', 'text': 'The first are setup scrubs, Or you can think of them as being configuration scrubs.', 'role': 'lecture'},
    {'sid': 's000557', 'text': "You have a system that's perfectly secure if it's configured correctly, but somebody didn't configure it correctly, perhaps because they didn't understand it, perhaps they were rushed and all that sort of thing.", 'role': 'lecture'},
    {'sid': 's000558', 'text': 'What sort of mistakes that can happen.', 'role': 'lecture'},
    {'sid': 's000559', 'text': 'Here is the configuration can specify the wrong security policy.', 'role': 'lecture'},
    {'sid': 's000560', 'text': 'The security policy, for example, might say something like this.', 'role': 'lecture'},
    {'sid': 's000561', 'text': 'The Chancellor can do anything that he wants with this computer system.', 'role': 'lecture'},
    {'sid': 's000562', 'text': "That's probably not a good idea, mostly because the Chancellor is a pretty busy guy and he's probably not going to mess with my desktop computer.", 'role': 'lecture'},
    {'sid': 's000563', 'text': "And if there is somebody logging in as the Chancellor to my computer, it's probably not really the Chancellor and all that sort of thing.", 'role': 'lecture'},
    {'sid': 's000564', 'text': "So that's the wrong policy.", 'role': 'lecture'},
    {'sid': 's000565', 'text': 'You do know, by the way, there is a policy in the parking system.', 'role': 'lecture'}
]

def main():
    load_dotenv()
    
    # Initialize Gemini client
    llm = UnifiedLLM(provider="gemini")
    
    # Read prompt instruction
    prompt_path = current_dir.parents[1] / "prompts" / "topic_details_generation_ver2.txt"
    if not prompt_path.exists():
        print(f"Error: Prompt file not found at {prompt_path}")
        return
        
    instr = prompt_path.read_text(encoding="utf-8")
    
    payload = {
        "task": "Topic Detail Generation",
        "instruction": instr,
        "data": {
            "topic": TOPIC,
            "partial-transcript": PARTIAL_TRANSCRIPT,
        },
    }
    
    messages = [
        Message(
            role="system",
            content="You are a careful lecture note generator. Follow the instructions strictly and keep the professor's nuance.",
        ),
        Message(
            role="user",
            content=json.dumps(payload, ensure_ascii=False),
        ),
    ]
    
    options = LLMOptions(
        output_type="text",
        temperature=0.2,
        google_search=False,
        max_output_tokens=8192,  # Set to absolute model limit to observe the full loop (costs ~2 cents max)
        provider_kwargs={"timeout_ms": 300000, "attempts": 1}  # 5 minutes timeout, 1 attempt (no retries)
    )
    
    print("Testing gemini-2.5-flash (No fallback, expecting to complete loop or time out)...")
    import time
    start = time.time()
    try:
        res = llm.generate(model="2_5_flash", messages=messages, options=options, fallback=False)
        elapsed = time.time() - start
        
        # Save output to text file in same folder
        output_txt_path = current_dir / "reproduce_output.txt"
        output_txt_path.write_text(res.output_text, encoding="utf-8")
        
        # Extract finish reason if available
        finish_reason = "Unknown"
        try:
            if res.raw and hasattr(res.raw, "candidates") and len(res.raw.candidates) > 0:
                finish_reason = str(res.raw.candidates[0].finish_reason)
        except Exception:
            pass

        # Save metadata to json file in same folder
        metadata = {
            "model_name": res.model_name,
            "elapsed_seconds": elapsed,
            "output_length_chars": len(res.output_text),
            "input_tokens": res.usage.input_tokens,
            "output_tokens": res.usage.output_tokens,
            "reasoning_tokens": res.usage.reasoning_tokens,
            "total_tokens": res.usage.total_tokens,
            "finish_reason": finish_reason,
        }
        metadata_json_path = current_dir / "reproduce_metadata.json"
        metadata_json_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        print(f"\n✅ Finished in {elapsed:.2f} seconds")
        print(f"Output Length: {len(res.output_text)} characters")
        print(f"Token Usage - Input: {res.usage.input_tokens}, Output: {res.usage.output_tokens}, Reasoning: {res.usage.reasoning_tokens}, Total: {res.usage.total_tokens}")
        print(f"Candidate Finish Reason: {finish_reason}")
        print(f"Saved results to:\n  - {output_txt_path.name}\n  - {metadata_json_path.name}")
        print("\n--- Preview of the last 500 characters ---")
        print(res.output_text[-500:])
    except Exception as e:
        elapsed = time.time() - start
        print(f"\n❌ Failed after {elapsed:.2f} seconds: {e}")

if __name__ == "__main__":
    main()
