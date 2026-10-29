<?xml version="1.0" encoding="utf-8" ?>
<!--
     Script to make oracle xml sql output somewhat friendlier:
     * lower case tags
     * specific document element name
     * document path in header
     * easy grouping

     Jurgen Hildebrand 20231124ß
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:fn="urn:xmlast:functions"
                xmlns:l="urn:xmlast:lineage"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                version="3.0" expand-text="yes" exclude-result-prefixes="fn xs l">
    <xsl:mode on-no-match="shallow-copy"/>
    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>

    <xsl:variable name="uri" select="base-uri()"/>
    <xsl:variable name="base" select="replace($uri,'.*src/main/xml/','')"/>
    <xsl:variable name="document-tag" select="replace($base,'.*/(.+)\.xml$','$1')"/>

    <!-- rules for various configuration files -->

    <xsl:template match="hcu-tables-to-clean" mode="categorise">
        <xsl:sequence select="fn:categorise(.,('hcu-group'),'group','table')"/>
    </xsl:template>

    <xsl:template match="distribution-definition" mode="categorise">
        <xsl:variable name="class-uri" select="replace($uri,'(.*)/.*$','$1/distribution_class.xml')"/>
        <xsl:variable name="distribution-class">
            <xsl:apply-templates select="doc($class-uri)/*" mode="reformat"/>
        </xsl:variable>
        <xsl:variable name="out" select="fn:categorise(.,('class-code'),'class','transfer')"/>
        <xsl:apply-templates select="$out" mode="class">
            <xsl:with-param name="distribution-class" select="$distribution-class" tunnel="true"/>
        </xsl:apply-templates>
    </xsl:template>

    <xsl:template match="class" mode="class">
        <xsl:param name="distribution-class" tunnel="true"/>
        <xsl:variable name="class-code" select="@class-code"/>
        <xsl:variable name="class-attrs"
                      select="$distribution-class//*[@class-code = $class-code]/(@* except @class-code)"/>
        <xsl:variable name="source-schema" select="fn:schema($class-attrs[name() = 'source-role'])"/>
        <xsl:variable name="target-schema" select="fn:schema($class-attrs[name() = 'target-role'])"/>
        <xsl:choose>
            <xsl:when test="$source-schema != $target-schema">
                <xsl:copy>
                    <xsl:apply-templates select="@*" mode="#current"/>
                    <xsl:copy-of select="$class-attrs"/>
                    <xsl:attribute name="source-schema" select="$source-schema"/>
                    <xsl:attribute name="target-schema" select="$target-schema"/>
                    <xsl:apply-templates select="node()" mode="#current"/>
                </xsl:copy>
            </xsl:when>
            <xsl:otherwise>
                <xsl:comment>skip: {$class-code} source and target schema are same: {$source-schema}</xsl:comment>
            </xsl:otherwise>
        </xsl:choose>

    </xsl:template>

    <xsl:function name="fn:schema">
        <xsl:param name="var"/>
        <xsl:variable name="schema" select="lower-case($var)"/>
        <xsl:choose>
            <xsl:when test="$schema = 'business'">buss</xsl:when>
            <xsl:when test="$schema = 'consumer'">cons</xsl:when>
            <xsl:otherwise>{$schema}</xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    <xsl:template match="raw-view-scope" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="fn:categorise(.,('subscription-id'),'subscription','column')">
                <xsl:sequence select="fn:categorise(subscription,('raw-view-name','active-ind'),'view')"/>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="raw-view-data" mode="categorise">
        <xsl:sequence select="fn:categorise(.,('subscription-id'),'subscription','table')"/>
    </xsl:template>

    <xsl:template match="raw-view-config" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="fn:categorise(.,('raw-view-name'),'view','column')"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="raw-view-type" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="fn:categorise(.,('type'),'types','type')"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="dmi-process-workflow-base|dmr-process-workflow-base" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="fn:categorise(.,('interface-type'),'interface','job')">
                <xsl:sequence select="fn:categorise(interface,('name'),'call')"/>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="vde-event|vpp-config" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="fn:categorise(.,('interface-type'),'interface','job')">
                <xsl:sequence select="fn:categorise(interface,('event-type'),'event')"/>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="vxx-dispatch" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="fn:categorise(.,('interface-type'),'interface','job')">
                <xsl:sequence select="fn:categorise(interface,('source-event-type'),'event')"/>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="vde-config" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="fn:categorise(.,('interface-type'),'interface','export')">
                <xsl:for-each select="fn:categorise(interface,('event-type'),'event','events')">
                    <xsl:copy>
                        <xsl:copy-of select="@*"/>
                        <xsl:sequence select="fn:categorise(event,('export-channel'),'channel','channels')"/>
                    </xsl:copy>
                </xsl:for-each>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="current_table" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="*">
                <xsl:sort select="@original-name"/>
                <xsl:apply-templates select="node()" mode="categorise"/>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="distribution_class" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="*">
                <xsl:sort select="@class-code"/>
                <xsl:apply-templates select="node()" mode="categorise"/>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="sdm_import_table_definition" mode="categorise">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select="*">
                <xsl:sort select="@target-table"/>
                <xsl:apply-templates select="node()" mode="categorise"/>
            </xsl:for-each>
        </xsl:copy>
    </xsl:template>
    <!-- first document element match rule -->

    <xsl:template match="/*">
        <xsl:variable name="reformatted">
            <xsl:element name="{fn:kebab-case($document-tag)}">
                <xsl:attribute name="uri" select="$base"/>
                <xsl:apply-templates select="*" mode="reformat"/>
            </xsl:element>
        </xsl:variable>
        <xsl:apply-templates select="$reformatted" mode="categorise"/>
    </xsl:template>

    <!-- reformat element in lower case -->

    <xsl:template match="*" mode="reformat">
        <xsl:element name="{fn:kebab-case(name())}">
            <xsl:apply-templates select="@*|node()" mode="reformat"/>
        </xsl:element>
    </xsl:template>

    <!-- turn elements underneath ROW to be attrs of output row -->

    <xsl:template match="ROW/*" mode="reformat">
        <xsl:attribute name="{fn:kebab-case(name())}" select="."/>
    </xsl:template>

    <!-- rename ROW to item -->

    <xsl:template match="ROW" mode="reformat">
        <item>
            <xsl:apply-templates select="@*|node()" mode="reformat"/>
        </item>
    </xsl:template>

    <!-- categorise: group elements underneath a parent element
         args:
         $container:  parent element of children to be grouped
         $group-by:   attribute names to use for grouping
         $group-name: new parent element name
         $item-name:  new child element name
    -->

    <xsl:function name="fn:categorise" as="node()*">
        <xsl:param name="container"/>
        <xsl:param name="group-by"/>
        <xsl:sequence select="fn:categorise($container,$group-by,'group','item')"/>
    </xsl:function>
    <xsl:function name="fn:categorise" as="node()*">
        <xsl:param name="container"/>
        <xsl:param name="group-by"/>
        <xsl:param name="group-name"/>
        <xsl:sequence select="fn:categorise($container,$group-by,$group-name,'item')"/>
    </xsl:function>
    <xsl:function name="fn:categorise" as="node()*">
        <xsl:param name="container"/>
        <xsl:param name="group-by"/>
        <xsl:param name="group-name"/>
        <xsl:param name="item-name"/>
            <xsl:for-each select="$container">
                <xsl:element name="{fn:kebab-case(name())}">
                    <xsl:copy-of select="@*"/>
                    <xsl:for-each-group select="*" group-by="string-join(@*[name() = $group-by],',')">
                        <xsl:sort select="current-grouping-key()"/>
                        <xsl:variable name="first" select="current-group()[1]"/>
                        <xsl:element name="{$group-name}">
                            <xsl:for-each select="$group-by">
                                <xsl:variable name="name" select="."/>
                                <xsl:attribute name="{$name}" select="$first/@*[name() = $name]"/>
                            </xsl:for-each>
                            <xsl:apply-templates select="current-group()" mode="filter">

                                <xsl:with-param name="filter" select="$group-by" tunnel="true"/>
                                <xsl:with-param name="item-name" select="$item-name" tunnel="true"/>
                            </xsl:apply-templates>
                        </xsl:element>
                    </xsl:for-each-group>
                </xsl:element>
            </xsl:for-each>
    </xsl:function>


    <!-- lower kebab-case case -->

    <xsl:function name="fn:kebab-case">
        <xsl:param name="in"/>
        {lower-case(translate($in,'_','-'))}
    </xsl:function>

    <!-- default match rules, some logic added here for sync to
         grab parts out of @query attribute such as
         _procedure and/or _query_table_name -->

    <xsl:template match="item" mode="filter">
        <xsl:param name="item-name" tunnel="true">item</xsl:param>
        <xsl:element name="{$item-name}">
            <xsl:if test="@query">
                <xsl:attribute name="name">
                    <xsl:analyze-string select="@query" regex="^\s*([_a-z0-9]+).*">
                        <xsl:matching-substring>{regex-group(1)}</xsl:matching-substring>
                        <xsl:non-matching-substring>{.}</xsl:non-matching-substring>
                    </xsl:analyze-string>
                </xsl:attribute>
                <xsl:variable name="query_table_name" as="xs:string?">
                    <xsl:analyze-string select="@query"
                                        regex="(v_table|i?v_table_name|v_aggr_table)\s*=&gt;\s*&apos;&apos;(.+?)&apos;&apos;">
                        <xsl:matching-substring>{regex-group(2)}</xsl:matching-substring>
                    </xsl:analyze-string>
                </xsl:variable>
                <xsl:if test="$query_table_name">
                    <xsl:attribute name="_query_table_name" select="$query_table_name"/>
                </xsl:if>
            </xsl:if>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:element>
    </xsl:template>

    <!-- below rule is used to remove attributes which are to be
         listed on parent elements because they where used for
         grouping -->

    <xsl:template match="@*|node()" mode="filter">
        <xsl:param name="filter" tunnel="true"/>
        <xsl:if test="not(name() = $filter)">
            <xsl:copy>
                <xsl:apply-templates select="@*|node()" mode="filter"/>
            </xsl:copy>
        </xsl:if>
    </xsl:template>

    <!-- default identity transform, copy node to output
         ande recurse -->

    <xsl:template match="@*|node()" mode="categorise">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    <xsl:template match="@*|node()" mode="class">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
</xsl:stylesheet>