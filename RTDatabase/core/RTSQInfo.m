//
//  RTSQInfo.m
//  RTSQLite
//
//  Created by ENUUI on 2018/5/3.
//  Copyright © 2018年 ENUUI. All rights reserved.
//

#import "RTSQInfo.h"
#import <objc/runtime.h>


#pragma mark - private interface
/** property type */
static rt_objc_t rt_object_type(rt_char_t *attr);

/** property type to bind type */
static rt_char_t *rt_sqlite3_bind_type(rt_char_t c);


static int rt_prepare_info(Class cls, rt_pro_info_p *proInfos, NSError **err);
static int rt_class_info_v(Class cls, int count, rt_pro_info_p *infos, BOOL *has_id);


#pragma mark - FUNCTION

void rt_free_str(char **str) {
    if (str == NULL) {
        return;
    }
    if (*str == NULL) {
        return;
    }
    free(*str);
    *str = 0x00;
}

// 获取class的名字
rt_char_t *rt_class_name(Class cls) {
    return object_getClassName(cls);
}

// ---------------------------------------------------
rt_objc_t rt_object_class_type(id obj) {
    if (!obj || [obj isKindOfClass:[NSNull class]]) {
        return '0';
    }
    
    rt_objc_t t = '0';
    rt_char_t *clsName = class_getName([obj class]);
    
    if (rt_str_compare(clsName, "NSTaggedPointerString")
        || rt_str_compare(clsName, "__NSCFConstantString")
        ) {
        t = rttext;
    } else if (rt_str_compare(clsName, "NSConcreteMutableData")
               || rt_str_compare(clsName, "_NSInlineData")
               ) {
        t = rtblob;
    } else if (rt_str_compare(clsName, "__NSDate")) {
        t = rtdate;
    } else if (rt_str_compare(clsName, "__NSCFBoolean")) {
        t = rtbool;
    } else if (rt_str_compare(clsName, "__NSCFNumber")) {
        if (rt_str_compare([obj objCType], @encode(char))) {
            t = rtchar;
        } else if (rt_str_compare([obj objCType], @encode(unsigned char))) {
            t = rtuchar;
        } else if (rt_str_compare([obj objCType], @encode(short))) {
            t = rtshort;
        } else if (rt_str_compare([obj objCType], @encode(unsigned short))) {
            t = rtushort;
        } else if (rt_str_compare([obj objCType], @encode(int))) {
            t = rtint;
        } else if (rt_str_compare([obj objCType], @encode(unsigned int))) {
            t = rtuint;
        } else if (rt_str_compare([obj objCType], @encode(long))) {
            t = rtlong;
        } else if (rt_str_compare([obj objCType], @encode(unsigned long))) {
            t = rtulong;
        } else if (rt_str_compare([obj objCType], @encode(long long))) {
            t = rtlong;
        } else if (rt_str_compare([obj objCType], @encode(unsigned long long))) {
            t = rtulong;
        } else if (rt_str_compare([obj objCType], @encode(float))) {
            t = rtfloat;
        } else if (rt_str_compare([obj objCType], @encode(double))) {
            t = rtdouble;
        }
    }
    return t;
}
// 获取property类型
static rt_objc_t rt_object_type(rt_char_t *attr) {
    
    if (strlen(attr) > 2) {
        char idx_1 = attr[1];
        if (idx_1 == '@') {
            if (strlen(attr) > 7    && // NSString
                attr[5]     == 'S'  &&
                attr[6]     == 't'  &&
                attr[7]     == 'r') {
                return rttext;
            } else if (strlen(attr) > 8    && // NSData
                       attr[6]     == 'a'  &&
                       attr[7]     == 't'  &&
                       attr[8]     == 'a') {
                return rtblob;
            } else if (strlen(attr) > 8    && // NSDate
                       attr[6]     == 'a'  &&
                       attr[7]     == 't'  &&
                       attr[8]     == 'e') {
                return rtdate;
            } else if (strlen(attr) > 8    && // NSNumber
                       attr[5]     == 'N'  &&
                       attr[6]     == 'u'  &&
                       attr[7]     == 'm') {
                return rtdouble;
            }
        } else if (idx_1 == 'c' || // char
                   idx_1 == 'C' || // unsigned char, Boolean
                   idx_1 == 's' || // short
                   idx_1 == 'S' || // unsigned short
                   idx_1 == 'i' || // int
                   idx_1 == 'I' || // unsigned int
                   idx_1 == 'q' || // long, long long
                   idx_1 == 'Q' || // unsigned long, unsigned long long, size_t
                   idx_1 == 'B' || // BOOL, bool
                   idx_1 == 'd' || // CGFloat, double
                   idx_1 == 'f') { // float
            return idx_1;
        }
    }
    return 0;
}

// 根据property类型 获取 bind 类型
static rt_char_t *rt_sqlite3_bind_type(rt_char_t t) {
    switch (t) {
        case rttext:
            return "TEXT";
        case rtblob:
            return "BLOB";
        case rtfloat:
        case rtdouble:
        case rtdate:
            return "REAL";
        case rtchar:
        case rtuchar:
        case rtshort:
        case rtushort:
        case rtint:
        case rtuint:
        case rtlong:
        case rtulong:
        case rtbool:
            return "INTEGER";
        default:
            return "";
            break;
    }
}

static int rt_class_info_v(Class cls, int count, rt_pro_info_p *infos, BOOL *has_id) {
    
    const char *clsName = class_getName(cls);
    
    if (cls == Nil || !clsName || strcmp(clsName, "NSObject") == 0) {
        return count;
    }
    
    unsigned int outCount;
    objc_property_t *proList = class_copyPropertyList(cls, &outCount);
    if (outCount == 0) {
        free(proList);
        return count;
    }
    
    int columnIdx = count;
    for (int i = 0; i < outCount; i++) {
        objc_property_t pro = proList[i];
        
        rt_char_t *cn = property_getName(pro);
        
        if (strlen(cn) == 0) continue;
        
        rt_objc_t t = rt_object_type(property_getAttributes(pro));
        if (t == 0) continue; // unkown type
        
        if (strcmp(cn, "_id") == 0) {
            if (has_id != NULL) {
                *has_id = YES;
            }
            continue;
        }
        
        // pro info
        rt_pro_info *next = rt_make_info(columnIdx + 1, t, cn);
        // sql
        rt_info_append(infos, next);
        
        columnIdx++;
    }
    
    return rt_class_info_v(class_getSuperclass(cls), columnIdx, infos, has_id);
}


static int rt_prepare_info(Class cls, rt_pro_info_p *proInfos, NSError **err) {
    
    rt_pro_info *infos = NULL;
    BOOL hasID = NO;
    int count = rt_class_info_v(cls, 0, &infos, &hasID);
    
    if (!hasID) {
        rt_error(@"RTDB can not find _id!", 105, err);
        if (infos != NULL) {
            rt_free_info(infos);
        }
        return 0;
    }
    if (proInfos) {
        *proInfos = infos;
    }
    return count;
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////
#pragma mark - @implementation RTSQInfo
//////////////////////////////////////////////////////

@interface RTSQInfo () {
    char        *_clsName;  // class name
    char        *_creat;    // creat sql
    char        *_insert;   // insert sql
    char        *_update;   // update sql
    char        *_delete;   // delete sql
    char        *_maxid;    // max _id sql
}
@property (nonatomic, assign) int count;
@end

@implementation RTSQInfo

- (instancetype)initWithClass:(Class)cls withError:(NSError *__autoreleasing*)error {
    if (self = [super init]) {
        _cls = cls;
        NSError *err;
        _count = rt_prepare_info(cls, &_prosInfo, &err);
        if (!err) {
            _has_id = YES;
        } else {
            if (error != NULL) {
                *error = err;
            }
        }
    }
    return self;
}

- (rt_char_t *)className {
    if (_clsName == NULL) {
        _clsName = (char *)class_getName(_cls);
    }
    return _clsName;
}

- (rt_char_t *)maxidSql {
    if (_maxid == NULL) {
        rt_str_append_v(&_maxid, "SELECT MAX(_id) FROM ", [self className], NULL);
    }
    return _maxid;
}

- (rt_char_t *)creatSql {
    if (_creat == NULL) {
        rt_str_append_v(&_creat, "CREATE TABLE if not exists '", [self className], "' ('_id' integer primary key autoincrement not null", NULL);
        for (rt_pro_info *pro = _prosInfo; pro != NULL; pro = pro->next) {
            rt_char_t *bindT = rt_sqlite3_bind_type(pro->t);
            rt_str_append_v(&self->_creat, ", '", pro->name, "' '", bindT, "'", NULL);
        }
       
        rt_str_append_v(&_creat, ")", NULL);
    }
    return _creat;
}

- (rt_char_t *)insertSql {
    if (_insert == NULL) {
        rt_str_append_v(&_insert, "INSERT INTO ", [self className], "(", NULL);
        char *names = NULL;
        char *values = NULL;
        
        int i = 0;
        for (rt_pro_info *pro = _prosInfo; pro != NULL; pro = pro->next) {
            BOOL end = ((self->_count - 1) == i);
            
            rt_str_append_v(&names, pro->name, end ? ")" : ", ", NULL);
            rt_str_append_v(&values, ":", pro->name,  end ? ")" : ", ", NULL);
            
            i++;
        }
        
        if (names != NULL && values != NULL) {
            rt_str_append_v(&_insert, names, " VALUES (", values, NULL);
        }
    }
    return _insert;
}

- (rt_char_t *)updateSql {
    if (_update == nil) {
        int i = 0;
        rt_str_append_v(&_update, "UPDATE ", [self className], " SET ", NULL);
        for (rt_pro_info *pro = _prosInfo; pro != NULL; pro = pro->next) {
            BOOL end = ((self.count - 1) == i);
            rt_str_append_v(&self->_update, pro->name, end ? " = ?" : " = ?, ", NULL);
            i++;
        }
        rt_str_append(&_update, 1, " WHERE _id = ", NULL);
    }
    return _update;
}

- (rt_char_t *)deleteSql {
    if (_delete == nil) {
        rt_str_append_v(&_delete, "DELETE FROM ", [self className], " WHERE _id = ", NULL);
    }
    return _delete;
}

- (rt_char_t *)updateSqlWithID:(NSInteger)_id {
    if ([self updateSql] == NULL)  return NULL;
    
    char *updateSql = (char *)calloc((strlen([self updateSql]) + rt_integer_digit(_id)), char_len);
    sprintf(updateSql, "%s%ld", [self updateSql], (long)_id);
    return (rt_char_t *)updateSql;
}

- (rt_char_t *)deleteSqlWithID:(NSInteger)_id {
    if ([self deleteSql] == NULL) return NULL;
    
    char *deleteSql = (char *)calloc((strlen([self deleteSql]) + rt_integer_digit(_id)), char_len);
    sprintf(deleteSql, "%s%ld", [self deleteSql], (long)_id);
    return (rt_char_t *)deleteSql;
}

- (void)dealloc {
    if (_prosInfo != NULL) {
        rt_free_info(_prosInfo);
    }
}
@end
